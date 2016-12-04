#!/bin/bash
#
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

#  "These are common commands used in various situations:"
#  "   source-bringup.sh -s aosp -b c6 -t android-6.0.1_61 -m"
#  "   source-bringup.sh -s caf -b c6 -t LA.BF64.1.2.2_rb4.44 -m"
#  "   source-bringup.sh -b c6 -t android-6.0.1_r61 -m -s"
#  "   source-bringup.sh -u <Gerrit Username> -g <Gerrit URL> -r 29418 -b c6 -p"
#  "   source-bringup.sh -u <Gerrit Username> -b c6 -p -g -r"

# Hardcode the name of the rom here
# This is only used when pushing merges to Github
# See function push
custom_rom="CandyRoms"

# This is the array of upstream repos we track
upstream=()

# This is the array of repos to blacklist and not merge
# Add or remove repos as you see fit
blacklist=('manifest' 'prebuilt' 'packages/apps/DeskClock')

# Colors
COLOR_RED='\033[0;31m'
COLOR_BLANK='\033[0m'
COLOR_GREEN='\033[0;32m'

function is_in_blacklist() {
  for j in ${blacklist[@]}
  do
    if [ "$j" == "$1" ]; then
      return 0;
    fi
  done
  return 1;
}

function get_repos() {
  if [ -f aosp-list ]; then
    rm -f aosp-list
  fi
  touch aosp-list
  declare -a repos=( $(repo list | cut -d: -f1) )
  curl --output /tmp/rebase.tmp $REPO --silent # Download the html source of the Android source page
  # Since their projects are listed, we can grep for them
  for i in ${repos[@]}
  do
    if grep -qw "$i" /tmp/rebase.tmp; then # If Google/CAF has it and
      if grep -qw "$i" ./.repo/manifest.xml; then # If we have it in our manifest and
        if grep -w "$i" ./.repo/manifest.xml | grep -qe "revision=\"$BRANCH\""; then # If we track our own copy of it
          if ! is_in_blacklist $i; then # If it's not in our blacklist
            upstream+=("$i") # Then we need to update it
            echo $i >> aosp-list
          else
            echo "================================================"
            echo " "
            echo "$i is in blacklist"
          fi
        fi
      fi
    fi
  done
  echo " "
  echo "I have found a total of ${#upstream[@]} repositories being tracked"
  echo "that will be checked for $TAG and merged if applicable."
  echo " "
  rm /tmp/rebase.tmp
}

function delete_upstream() {
  for i in ${upstream[@]}
  do
    rm -rf $i
  done
}

function force_sync() {
  echo "================================================"
  echo "                                                "
  echo "          Force Syncing all your repos          "
  echo "         and deleting all upstream repos        "
  echo " This is done so we make sure you're up to date "
  echo "                                                "
  echo "================================================"
  echo " "

  echo "Repo Syncing........."
  sleep 10
  repo sync --force-sync >/dev/null 2>&1; # Silence!
  if [ $? -eq 0 ]; then
    echo "Repo Sync success"
  else
    echo "Repo Sync failure"
    exit 1
  fi
}

function print_result() {
  if [ ${#failed[@]} -eq 0 ]; then
    echo " "
    echo "========== "$TAG" is merged sucessfully =========="
    echo "========= Compile and test before pushing to github ========="
    echo " "
  else
    echo -e $COLOR_RED
    echo -e "These repos have merge errors: \n"
    for i in ${failed[@]}
    do
      echo -e "$i"
    done
    echo -e $COLOR_BLANK
  fi
}

function merge() {
  while read path; do

    project=`echo ${path} | sed -e 's/\//\_/g'`

    echo " "
    echo "====================================================================="
    echo " "
    echo " PROJECT: ${project} -> [ ${path}/ ]"
    echo " "

    cd $path;

    git merge --abort >/dev/null 2>&1; # Silence!

    repo sync -d .

    if [ "$aosp" = "1" ]; then
      if git branch | grep "android-aosp-merge" > /dev/null; then
        echo -e $COLOR_GREEN
        echo "Deleting branch android-aosp-merge"
        git branch -D android-aosp-merge > /dev/null
        echo "Recreating branch android-aosp-merge"
        repo start android-aosp-merge .
        echo -e $COLOR_BLANK
      else
        echo -e $COLOR_GREEN
        echo "Creating branch android-aosp-merge"
        repo start android-aosp-merge .
        echo -e $COLOR_BLANK
      fi
    fi
    if [ "$aosp" = "1" ]; then
      if ! git remote | grep "aosp" > /dev/null; then
        git remote add aosp https://android.googlesource.com/platform/$path > /dev/null
        git fetch --tags aosp
      else
        git fetch --tags aosp
      fi
    fi
    if [ "$caf" = "1" ]; then
      if git branch | grep "android-caf-merge" > /dev/null; then
        echo -e $COLOR_GREEN
        echo "Deleting branch android-caf-merge"
        git branch -D android-caf-merge > /dev/null
        echo "Recreating branch android-caf-merge"
        repo start android-caf-merge .
        echo $COLOR_BLANK
      else
        echo -e $COLOR_GREEN
        echo "Creating branch android-caf-merge"
        repo start android-caf-merge .
        echo -e $COLOR_BLANK
      fi
    fi
    if [ "$caf" = "1" ]; then
      if ! git remote | grep "caf" > /dev/null; then
        git remote add caf https://source.codeaurora.org/quic/la/platform/$path > /dev/null
        git fetch --tags caf
      else
        git fetch --tags caf
      fi
    fi

    if [ "$aosp" = "1" ]; then
      git merge $TAG;
    else
      git merge caf/$TAG;
    fi

    if [ $? -ne 0 ]; then # If merge failed
      failed+=($path/) # Add to the list of failed repos
    fi

    cd - > /dev/null

  done < aosp-list
}

function push () {
  while read path;
    do

    project=`echo android_${path} | sed -e 's/\//\_/g'`

    echo ""
    echo "====================================================================="
    echo " PROJECT: ${project} -> [ ${path}/ ]"
    echo ""

    cd $path;

    echo " Pushing..."

    git push --no-thin ssh://${USERNAME}@${GERRIT}:${PORT}/${custom_rom}/${project} HEAD:refs/heads/${BRANCH} >/dev/null 2>&1; # Silence!
    if [ $? -ne 0 ]; then # If merge failed
      echo " "
      echo "Failed to push ${project} to HEAD:refs/heads/${BRANCH}"
    else
      echo " Success!"
    fi

    cd - > /dev/null

  done < aosp-list
}

# Let's parse the users commands so that their order is not required.
# Credits to Noah Hoffman for making it possible to use Python's argparse module in shell scripts.
# See, https://github.com/nhoffman/argparse-bash, for more details.
# Python 2.6+ or 3.2+ is required for this to work.
# TODO: Rewrite this entire script in Python.

source $(dirname $0)/Scripts/argparse.bash || exit 1
argparse "$@" <<EOF || exit 1
parser.add_argument('-s', dest='source', help='Target AOSP or CAF [AOSP is default]', nargs='?', const="aosp",
                    default="aosp")
parser.add_argument('-t', dest='tag', help='The tag from AOSP or CAF that we are merging')
parser.add_argument('-b', dest='branch', help='Your default branch', required=True)
parser.add_argument('-u', dest='username', help='Your username on Gerrit')
parser.add_argument('-g', dest='gerrit', help='URL Gerrit '
                    '[gerrit.bbqdroid.org is default]', nargs='?', const="gerrit.bbqdroid.org",
                    default="gerrit.bbqdroid.org")
parser.add_argument('-r', dest='port', help='Which port SSH listens on for Gerrit '
                    '[29418 is default]', nargs='?', const="29418", default="29418")
parser.add_argument('-m', dest='merge', help='Merge the specified tag '
                    '[No arg required]', nargs='?', const="merge")
parser.add_argument('-p', dest='push', help='Push merge to Github through Gerrit '
                    '[No arg required]', nargs='?', const="push")

EOF

if [ -z $USERNAME ] && [ -n $PUSH ]; then
  echo ""
  echo "source-bringup.sh: error: argument -u is required"
  echo ""
  exit 0
fi

if [ -z $TAG ] && [ -n $MERGE ]; then
  echo ""
  echo "source-bringup.sh: error: argument -t is required"
  echo ""
  exit 0
fi

case "${SOURCE}" in
  # Google source
  [aA][oO][sS][pP]) REPO=https://android.googlesource.com/platform/; aosp=1; caf=0; get_repos ;;
  # Code Aurora source
  [cC][aA][fF]) REPO=https://source.codeaurora.org/quic/la/platform/; aosp=0; caf=1; get_repos ;;
  # Wrong entry, try again
  *) echo " "; echo "Did you mean AOSP or CAF? I am confused!"; sleep 1 ;;
esac

if [[ $MERGE =~ ^([mM][eE][rR][gG][eE])$ ]]; then
  delete_upstream # Clean up sources
  force_sync # Force sync sources
  merge # Bringup sources to latest code
  print_result # Print any repos that failed, so we can fix merge issues
fi

if [[ $PUSH =~ ^([pP][uU][sS][hH])$ ]]; then
  push # Push latest changes through gerrit straight to github
fi
