#!/bin/sh

# Load the stored version information if we have it
if test -f stored-version.sh
then
	. stored-version.sh
fi

# Obtain GIT commit ID
if git_commit_id=`git rev-parse --verify HEAD 2>/dev/null`
then
	# Copy what we got for retention
	GIT_COMMIT_ID=$git_commit_id

	# Determine the tag of this version
	GIT_TAG=`git describe --tags 2>/dev/null`

	# Determine if our checkout contains modifications not yet committed
	if git diff-index --name-only HEAD | read -r foo
	then
		IS_DIRTY="Y"
	else
		IS_DIRTY="N"
	fi

	# Chop up tag to get major, minor, extra
	if echo $GIT_TAG | grep -E '^v' > /dev/null
	then
		# Remove trailing context supplied by git and store final tag form
		short_tag=`echo $GIT_TAG | sed 's/^v//' | sed 's/[^a-z0-9\.].*$//'`

		# Extract version components
		MAJOR=`echo $short_tag | cut -d. -f1`
		MINOR=`echo $short_tag | cut -d. -f2`
		EXTRA=`echo $short_tag | cut -d. -f3`

		VERSTRING=$GIT_TAG
	else
		# Define zero values if we can't interpret the tag
		MAJOR=0
		MINOR=0
		EXTRA=0
		VERSTRING="v0.0.0"
	fi

	# Add -dirty if necessary
	if [ "f$IS_DIRTY" == "fY" ]
	then
		VERSTRING="$VERSTRING-dirty"
	fi
fi

# Cast to numbers
MAJOR=`expr $MAJOR + 0`
MINOR=`expr $MINOR + 0`
EXTRA=`expr $EXTRA + 0`

echo "MAJOR=$MAJOR"
echo "MINOR=$MINOR"
echo "EXTRA=$EXTRA"

# Assemble build string
BUILD_DATE=`date`
BUILD_HOST=`hostname`
BUILT_BY=`whoami`
BUILD_STR="built by $BUILT_BY on $BUILD_HOST at $BUILD_DATE"

# Emit stored-version.sh file
echo "GIT_COMMIT_ID=\"$GIT_COMMIT_ID\"" > stored-version.sh
echo "GIT_TAG=\"$GIT_TAG\"" >> stored-version.sh
echo "VERSTRING=\"$VERSTRING\"" >> stored-version.sh
echo "MAJOR=\"$MAJOR\"" >> stored-version.sh
echo "MINOR=\"$MINOR\"" >> stored-version.sh
echo "EXTRA=\"$EXTRA\"" >> stored-version.sh

# Emit stored-version.pm file
echo "package CorosyncCPGVersion;" > stored-version.pm
echo "\$GIT_COMMIT_ID=\"$GIT_COMMIT_ID\";" >> stored-version.pm
echo "\$GIT_TAG=\"$GIT_TAG\";" >> stored-version.pm
echo "\$VERSTRING=\"$VERSTRING\";" >> stored-version.pm
echo "\$MAJOR=\"$MAJOR\";" >> stored-version.pm
echo "\$MINOR=\"$MINOR\";" >> stored-version.pm
echo "\$EXTRA=\"$EXTRA\";" >> stored-version.pm
echo "1;" >> stored-version.pm

