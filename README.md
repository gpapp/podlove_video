# podlove_video
Script to generate image and video artifacts for Podlove based podcasts

# Assumptions/Pre-requesites

You need to run the current version of Podlove, on a WordPress instance, which uses MySQL backend.
Your served podcast files are contained in a single directory.
You have a SRC folder that contains a directory for each episode named after the episode slug. The directory needs to contain an image file called YOUR_SLUG.png, YOUR_SLUG.jpg, and YOUR_SLUG.psc that contains a PSC file for the chapters to be generated.

You are running a POSIX compatible OS, with ffmpeg, perl:xpath, eyeD3 installed from the repository of your OS.

# Setup
Create a file called .env containing the following lines

`
SSH_CMD="sudo -u USER ssh USER@HOSTNAME"
MYSQL_DB="YOUR VALUES HERE"
MYSQL_USER="YOUR VALUES HERE"
MYSQL_PASSWORD="YOUR VALUES HERE"
MYSQL_PREFIX="YOUR VALUES HERE"
`

take the values from your WP installation.

If you are running MySql on the local instance adjust the SSH_CMD accordingly.

Modify the script and replace your values:

`
SRC_DIR="SOURCE_DIRECTORY"
TARGET_DIR="TARGET_DIRECTORY"
LOGO=${SRC_DIR}/logo.jpg
PODCAST_TITLE="PODCAST_TITLE"
CDN_BASE_URL="BASE_URL"
`

# Usage

`
./generate_video 000 [-f] [-i] [-e]
`

Run the script with the episode number (padded with 0!) to generate the 
 * cover,
 * title,
 * chapter index,
 * chapter image
files. The mp3 file will be modified to add the cover to its ID3 tag.

The output of the command will be the template that can be used to be added when uploading to YT or Meta.

## Flags
* -f flag forces episode fetch and regeneration
* -i only regenerates images (no video)
* -e can be used to define episode number

If the -f flag is not specified, and the episode_export.txt is less than a day old, episode information will not be refetched
and only missing files will be created. This is useful, when you want to create the episode descriptions for yt/google exports.

## Example

Generate artifacts for episode 123

`
./generate_video 123
`

Regenerating the first 200 episodes

`
for i in $(seq 001 200); do ./generate_video $i; done
`