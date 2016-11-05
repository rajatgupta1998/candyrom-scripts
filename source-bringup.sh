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

export USAGE=(
  "USAGE: source-bringup.sh [-s | --source] [-b | --branch] [-m | --merge]"
  "                         [-p | --push] [-u | --username] [-g | --gerrit]"
  "                         [-P | --port]"
  ""
  "Defining each option:"
  "   -s | --source (Target AOSP or CAF [AOSP is default])"
  ""
  "   -t | --tag (The tag from AOSP or CAF that we are merging)"
  ""
  "   -b | --branch (The branch you are targeting from your repos - required)"
  ""
  "   -m | --merge (Merge the specified branch - [optional <No arg required>])"
  ""
  "   -p | --push (Push git history to Github - [optional <No arg required>])"
  ""
  "   -u | --username (Your username on Gerrit)"
  ""
  "   -g | --gerrit (URL Gerrit instance which we are pushing to [Candy Gerrit is default])"
  "                 (Changes pushed to Gerrit will be sent to Github)"
  ""
  "   -P | --port (Which port Gerrit SSH listens on - [29418 is default])"
  ""
  "These are common commands used in various situations:"
  "   source-bringup.sh -s aosp -b c6 -t android-6.0.1_61 -m"
  "   source-bringup.sh --source caf --branch c6 --tag LA.BF64.1.2.2_rb4.44 --merge"
  "   source-bringup.sh -b c6 -t android-6.0.1_r61 -m -s"
  "   source-bringup.sh -u <Gerrit Username> -g <Gerrit URL> -P 29418 -b c6 -p"
  "   source-bringup.sh --username <Gerrit Username> --gerrit <Gerrit URL> --port 29418 --branch c6 --push"
  "   source-bringup.sh -u <Gerrit Username> -b c6 -p -g -p"
)

function call_usage () {
  for c in ${!USAGE[*]}; do
    echo -e "- ${USAGE[$c]}"
  done
}

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

# Let's parse the users commands so that their order is not required
# Then store the following commands in variables
# If there is an issue with any commands then we can abort
# This method isn't perfect but it works - for now
if [ "$#" -eq 0 ];then
  echo " "
  call_usage
  exit 0
fi

pointer=1
while [ $pointer -le $# ]; do
  param=${!pointer}
  if [[ $param != "-"* ]]; then ((pointer++)) # not a parameter flag so advance pointer
  else
    param=${!pointer}
    ((pointer_plus = pointer + 1))
    slice_len=1
    case $param in
      -s*|--source) SOURCE=${!pointer_plus:-AOSP}; ((slice_len++));;
      -t*|--tag) TAG=${!pointer_plus}; ((slice_len++));;
      -b*|--branch) BRANCH=${!pointer_plus}; ((slice_len++));;
      -m*|--merge) MERGE="merge";;
      -p*|--push) PUSH="push";;
      -u*|--username) USERNAME=${!pointer_plus}; ((slice_len++));;
      -g*|--gerrit) GERRIT=${!pointer_plus:-gerrit.bbqdroid.org}; ((slice_len++));;
      -P*|--port) PORT=${!pointer_plus:-29418}; ((slice_len++));;
      *) echo Unknown option: $param >&2; echo " "; sleep 1; call_usage; exit 0;;
    esac
    # splice out pointer frame from positional list
    [[ $pointer -gt 1 ]] \
      && set -- ${@:1:((pointer - 1))} ${@:((pointer + $slice_len)):$#} \
      || set -- ${@:((pointer + $slice_len)):$#};
  fi
done

case "${SOURCE}" in
  # Google source
  [aA][oO][sS][pP]) REPO=https://android.googlesource.com/platform/; aosp=1; caf=0; get_repos ;;
  # Code Aurora source
  [cC][aA][fF]) REPO=https://source.codeaurora.org/quic/la/platform/; aosp=0; caf=1; get_repos ;;
  # Wrong entry, try again
  *) echo " "; echo "Did you mean AOSP or CAF? I am confused!"; sleep 1; echo " "; call_usage ;;
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
