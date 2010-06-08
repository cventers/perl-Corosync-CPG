#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"

#include <corosync/cpg.h>
#include <sys/uio.h>

/* name a type for our handle pointer */
typedef cpg_handle_t *
CorosyncCPGHandle;

/* callback functions from libcpg */
static cpg_callbacks_t
cpg_callbacks;

/* (diagnostic only) c shortcut for Devel::Peek::Dump(sv); */
static void
cpgc_dumpsv (SV *tmp)
{
    dTHX;
    Perl_do_sv_dump(aTHX_ 0, Perl_debug_log, tmp, 0, 4, FALSE, 0);
}

/* sets the last error on %self */
static void
cpgc_seterr (HV * self, cs_error_t err)
{
    dTHX;

    /* set error code */
    if (hv_store(self, "_cs_error", 9, newSViv((int)err), 0) == NULL) {
        Perl_croak(aTHX_ "Unable to set _cs_error");
    }
}

/* type-safely grabs our libcpg handle ptr out of %self */
static CorosyncCPGHandle
cpgc_gethandle (pTHX_ HV * self)
{
    CorosyncCPGHandle handle;
    IV int_handle;
    SV **sv;

    /* fetch and verify handle */
    sv = hv_fetch(self, "_cpg_handle", 11, 0);
    if (sv == NULL || !sv_derived_from(*sv, "CorosyncCPGHandle")) {
        Perl_croak(aTHX_ "_cpg_handle 0x%p is not of type CorosyncCPGHandle", sv);
    }

    /* deref scalar, obtain pointer */
    int_handle = SvIV((SV*)SvRV(*sv));
    handle = INT2PTR(CorosyncCPGHandle, int_handle);
    return handle;
}

/* populates a cpg_name, checking name requirements in the process */
static void
cpgc_setname (pTHX_ struct cpg_name *group, SV *sv)
{
    char *namebuf;
    if (!SvOK(sv)) {
        Perl_croak(aTHX_ "name is not a valid scalar!");
    }
    namebuf = SvPV((SV*)sv, group->length);
    if (group->length > sizeof(group->value)) {
        Perl_croak(aTHX_ "name is too long!");
    }
    else if (group->length == 0) {
        Perl_croak(aTHX_ "name is empty!");
    }
    strncpy(group->value, namebuf, sizeof(group->value));
}

/* builds a hash to describe a cpg_address */
HV *
cpgc_cpg_address_unpack (const struct cpg_address *address, int need_reason)
{
    dTHX;
    HV *hv;
    hv = newHV();
    if (hv == NULL)
        goto error;
    if (hv_store(hv, "nodeid", 6, newSViv(address->nodeid), 0) == NULL)
        goto error;
    if (hv_store(hv, "pid", 3, newSViv(address->pid), 0) == NULL)
        goto error;
    if (need_reason) {
        if (hv_store(hv, "reason", 6, newSViv(address->reason), 0) == NULL)
            goto error;
    }
    return hv;

error:
    Perl_croak(aTHX_ "Unable to unpack cpg_address");
}

/* fires off deliver callback */
static void
cpgc_deliver (cpg_handle_t handle,
              const struct cpg_name *group_name,
              uint32_t nodeid,
              uint32_t pid,
              void *msg,
              size_t msg_len)
{
    dSP;
    HV *stash;
    HV *self;
    GV *gv;

    /* get the perl object and stash for this cpg handle */
    cpg_context_get(handle, (void**)&self);
    stash = SvSTASH(self);

    /* get code value for deliver hook */
    gv = gv_fetchmeth(stash, "_cb_deliver", 11, 0);
    if (!gv)
        return;

    /* enter perl context */
    ENTER;
    SAVETMPS;
    PUSHMARK(SP);

    /* add arguments */
    XPUSHs(sv_2mortal((SV*)newRV((SV*)self)));
    XPUSHs(sv_2mortal((SV*)newSVpv(group_name->value, group_name->length)));
    XPUSHs(sv_2mortal((SV*)newSViv(nodeid)));
    XPUSHs(sv_2mortal((SV*)newSViv(pid)));
    XPUSHs(sv_2mortal((SV*)newSVpv(msg, msg_len)));

    /* done building stack */
    PUTBACK;

    /* fire off our callback */
    call_sv((SV*)GvCV(gv), G_VOID);

    /* reaquire stack */
    SPAGAIN;

    /* done */
    FREETMPS;
    LEAVE;
}

/* create an AV from the member list */
AV *
cpgc_cpg_address_list_unpack (
    const struct cpg_address *member_list,
    size_t member_list_size,
    int need_reason
)
{
    AV *av = newAV();
    HV *hv;
    int i;

    for (i = 0; i < member_list_size; i++) {
        hv = cpgc_cpg_address_unpack(&member_list[i], need_reason);
        av_store(av, i, newRV_noinc((SV*)hv));
    }

    return av;
}

/* configuration change callback from libcpg */
static void
cpgc_confchg (cpg_handle_t handle,
              const struct cpg_name *group_name,
              const struct cpg_address *member_list,
              size_t member_list_entries,
              const struct cpg_address *left_list,
              size_t left_list_entries,
              const struct cpg_address *joined_list,
              size_t joined_list_entries)
{
    dSP;
    AV *mlav, *llav, *jlav;
    HV *stash;
    HV *self;
    GV *gv;
    
    /* get the perl object and stash for this cpg handle */
    cpg_context_get(handle, (void**)&self);
    stash = SvSTASH(self);

    /* get code value for confchg hook */
    gv = gv_fetchmeth(stash, "_cb_confchg", 11, 0);
    if (!gv)
        return;

    /* build address arrays */
    mlav = cpgc_cpg_address_list_unpack(member_list, member_list_entries, 0);
    llav = cpgc_cpg_address_list_unpack(left_list, left_list_entries, 1);
    jlav = cpgc_cpg_address_list_unpack(joined_list, joined_list_entries, 1);

    /* enter perl context */
    ENTER;
    SAVETMPS;
    PUSHMARK(SP);

    /* add arguments */
    XPUSHs(sv_2mortal(newRV((SV*)self)));
    XPUSHs(sv_2mortal((SV*)newSVpv(group_name->value, group_name->length)));
    XPUSHs(sv_2mortal(newRV((SV*)mlav)));
    XPUSHs(sv_2mortal(newRV((SV*)llav)));
    XPUSHs(sv_2mortal(newRV((SV*)jlav)));

    /* done building stack */
    PUTBACK;

    /* fire off our callback */
    call_sv((SV*)GvCV(gv), G_VOID);

    /* reaquire stack */
    SPAGAIN;

    /* done */
    FREETMPS;
    LEAVE;
}

MODULE = Corosync::CPG  PACKAGE = Corosync::CPG  PREFIX=cpgc_

BOOT:
    /* set up callbacks here to avoid link-time relocs */
    cpg_callbacks.cpg_deliver_fn = &cpgc_deliver;
    cpg_callbacks.cpg_confchg_fn = &cpgc_confchg;

CorosyncCPGHandle
cpgc__initialize(self)
        HV * self
    PREINIT:
        CorosyncCPGHandle handle;
        cs_error_t ret;
    CODE:
        /* allocate a handle */
        Newz(0, handle, 1, cpg_handle_t);

        /* connect to corosync */
        ret = cpg_initialize(handle, &cpg_callbacks);
        cpgc_seterr(self, ret);
        if (ret == CPG_OK) {
            cpg_context_set(*handle, self);
            RETVAL = handle;
        }
        else {
            Safefree(handle);
            XSRETURN_UNDEF;
        }
    OUTPUT:
        RETVAL


int
cpgc__fd_get(self)
        HV * self
    PREINIT:
        CorosyncCPGHandle handle;
        cs_error_t ret;
        int fd;
    CODE:
        handle = cpgc_gethandle(aTHX_ self);

        /* get our fd to the corosync executive */
        ret = cpg_fd_get(*handle, &fd);
        cpgc_seterr(self, ret);
        if (ret == CPG_OK) {
            RETVAL = fd; 
        }
        else {
            XSRETURN_UNDEF;
        }
    OUTPUT:
        RETVAL

int
cpgc__dispatch(self, type)
        HV *self
        cs_dispatch_flags_t type
    PREINIT:
        CorosyncCPGHandle handle;
        cs_error_t ret;
    CODE:
        handle = cpgc_gethandle(aTHX_ self);

        /* fire off libcpg dispatches */
        ret = cpg_dispatch(*handle, type);
        cpgc_seterr(self, ret);
        if (ret == CPG_OK) {
            RETVAL = 1;
        }
        else {
            XSRETURN_UNDEF;
        }
    OUTPUT:
        RETVAL

int
cpgc__join(self, name)
        HV *self
        SV *name
    PREINIT:
        CorosyncCPGHandle handle;
        cs_error_t ret;
        struct cpg_name group;
    CODE:
        cpgc_setname(aTHX_ &group, name);
        handle = cpgc_gethandle(aTHX_ self);

        /* join group */
        ret = cpg_join(*handle, &group);
        cpgc_seterr(self, ret);
        if (ret == CPG_OK) {
            RETVAL = 1;
        }
        else {
            XSRETURN_UNDEF;
        }
    OUTPUT:
        RETVAL

int
cpgc__leave(self, name)
        HV *self
        SV *name
    PREINIT:
        CorosyncCPGHandle handle;
        cs_error_t ret;
        struct cpg_name group;
    CODE:
        cpgc_setname(aTHX_ &group, name);
        handle = cpgc_gethandle(aTHX_ self);

        /* leave group */
        ret = cpg_leave(*handle, &group);
        cpgc_seterr(self, ret);
        if (ret == CPG_OK) {
            RETVAL = 1;
        }
        else {
            XSRETURN_UNDEF;
        }
    OUTPUT:
        RETVAL

int
cpgc__local_get(self)
        HV *self
    PREINIT:
        CorosyncCPGHandle handle;
        cs_error_t ret;
        uint32_t nodeid;
    CODE:
        handle = cpgc_gethandle(aTHX_ self);

        /* get local nodeid */
        ret = cpg_local_get(*handle, &nodeid);
        if (ret == CPG_OK) {
            RETVAL = nodeid;
        }
        else {
            XSRETURN_UNDEF;
        }
    OUTPUT:
        RETVAL

AV *
cpgc__membership_get(self, name)
        HV *self
        SV *name
    PREINIT:
        AV *av;
        CorosyncCPGHandle handle;
        cs_error_t ret;
        struct cpg_name group;
        struct cpg_address *member_list;
        int member_list_size = 8;
        int submitted_size;
    CODE:
        cpgc_setname(aTHX_ &group, name);
        handle = cpgc_gethandle(aTHX_ self);
        
        /* get initial list size */
        ret = cpg_membership_get(*handle, &group, 0, &member_list_size);
	cpgc_seterr(self, ret);
        if (ret != CPG_OK) {
            XSRETURN_UNDEF;
        }

        /* allocate a temporary buffer to get the addresses back */
        New(0, member_list, member_list_size, struct cpg_address);
        SAVEFREEPV(member_list);

        /* repeatedly try and get the whole list, growing the buffer as
           needed 
         */
        while (1) {
            submitted_size = member_list_size;

            ret = cpg_membership_get(*handle, &group, member_list,
                                     &member_list_size);
            cpgc_seterr(self, ret);
            if (ret == CPG_OK) {
                if (member_list_size > submitted_size) {
                    Renew(member_list, member_list_size, struct cpg_address);
                    continue;
                }
                else {
                    break;
                }
            }
            else {
                XSRETURN_UNDEF;
            }
        }

        /* build return array from cpg_address list */
        av = cpgc_cpg_address_list_unpack(member_list, member_list_size, 0);

        RETVAL = av;
    OUTPUT:
        RETVAL

int
cpgc__flow_control_state_get(self)
        HV *self
    PREINIT:
        CorosyncCPGHandle handle;
        cs_error_t ret;
        cpg_flow_control_state_t flow_control_enabled;
    CODE:
        handle = cpgc_gethandle(aTHX_ self);

        /* get flow control state */
        ret = cpg_flow_control_state_get(*handle, &flow_control_enabled);
        cpgc_seterr(self, ret);
        if (ret == CPG_OK) {
            RETVAL = (int)flow_control_enabled;
        }
        else {
            XSRETURN_UNDEF;
        }
    OUTPUT:
        RETVAL

int
cpgc__mcast_joined(self, guarantee, ...)
        HV *self
        cpg_guarantee_t guarantee;
    PREINIT:
        CorosyncCPGHandle handle;
        cs_error_t ret;
        int buffers;
        SV *item;
        int i;
        struct iovec *iovec;
    CODE:
        handle = cpgc_gethandle(aTHX_ self);

        /* make sure we have buffers to send */
        if (items <= 2) {
            Perl_croak(aTHX_ "no buffers specified!");
        }

        /* build a temporary iovec array for the buffers */
        buffers = items - 2;
        New(0, iovec, buffers, struct iovec);
        SAVEFREEPV(iovec);

        /* make sure the buffers are good buffers, build an iovec for them */
        for (i = 0; i < buffers; i++) {
            item = ST(i+2);
            if (!SvOK(item)) {
                Perl_croak(aTHX_ "bad buffer type; expect scalar");
            }
            iovec[i].iov_base = SvPV((SV*)item, iovec[i].iov_len);
        }

        /* send message */
        ret = cpg_mcast_joined(*handle, guarantee, iovec, buffers);
        cpgc_seterr(self, ret);
        if (ret == CPG_OK) {
            RETVAL = 1;
        }
        else {
            XSRETURN_UNDEF;
        }
    OUTPUT:
        RETVAL

MODULE = Corosync::CPG  PACKAGE = CorosyncCPGHandle  PREFIX=cpgchp_


void
cpgchp_DESTROY(ptr)
        CorosyncCPGHandle ptr
    CODE:
        if (ptr)
            cpg_finalize(*ptr);
        Safefree(ptr);

