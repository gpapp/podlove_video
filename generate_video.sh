#!/bin/bash
SRC_DIR="/data/podcast/src"
TARGET_DIR="/data/podcast/podcast"
LOGO=${SRC_DIR}/logo.jpg
PODCAST_TITLE="Zártosztály Podcast"
CDN_BASE_URL="https://cdn.zartosztaly.hu/podcast"
FONT="-font Liberation-Sans"

function export_from_mysql () {
    source .env
    if [ -z $"SSH_CMD" ] || [ -z $"MYSQL_DB" ] || [ -z "MYSQL_USER" ] || [ -z "MYSQL_PASSWORD" ]|| [ -z "MYSQL_PREFIX" ]; then
	echo 'Please set the variables "SSH_CMD", "MYSQL_DB", "MYSQL_USER", "MYSQL_PASSWORD", "MYSQL_PREFIX" in the .env file next to this script'
	exit
    fi

    MYSQL_CMD="${SSH_CMD} mysql ${MYSQL_DB} -u${MYSQL_USER} -p${MYSQL_PASSWORD} -B"
    ${MYSQL_CMD} << EOM
SET SESSION group_concat_max_len = 8172;
select ep.number, ep.slug, ep.title, date_format(ep.recording_date,"%Y-%m-%dT%H:%i:%sZ"), date_format(po.post_date,"%Y-%m-%dT%H:%i:%sZ"), kw.kw, ep.summary, se.links
        from ${MYSQL_PREFIX}podlove_episode ep
        left join ${MYSQL_PREFIX}posts po on ep.post_id=po.id and po.post_status not in ("inherit", "auto-draft")
	left join (select sep.id id, group_concat(concat(se.title,": ",se.original_url) SEPARATOR "\\n") as links from ${MYSQL_PREFIX}podlove_modules_shownotes_entry se, ${MYSQL_PREFIX}podlove_episode sep where sep.id=se.episode_id group by sep.id) se on se.id=ep.id 
        left join (select tr.object_id, group_concat(t.name SEPARATOR ", ") as kw from ${MYSQL_PREFIX}terms t, ${MYSQL_PREFIX}term_relationships tr, ${MYSQL_PREFIX}term_taxonomy tx where t.term_id=tx.term_id and tr.term_taxonomy_id=tx.term_taxonomy_id group by tr.object_id) kw on kw.object_id=po.id 
        where ep.number is not NULL and po.post_status not in ("auto-draft","inherit")
EOM
#        left join (select pm.post_id, pt.guid from ${MYSQL_PREFIX}postmeta pm,${MYSQL_PREFIX}posts pt where pm.meta_key="_thumbnail_id" and pt.id=pm.meta_value) th on th.post_id=po.id where ep.number is not NULL and po.post_status not in ("auto-draft","inherit")
}

function load_ep_data_SQL () {
    local episode=$1
    if [ ! -e episode_export.txt -o "$(find episode_export.txt -mtime +1)" ]; then
        export_from_mysql >episode_export.txt
    fi
    IFS=$'|' read -r _ EPISODE_SLUG EPISODE_TITLE EPISODE_REC_DATE EPISODE_POST_DATE EPISODE_KEYWORDS EPISODE_SUMMARY <<< \
        $( awk -F"\t" -r -v ep=${episode} '{if ($1==ep) {print gensub(/\t/,"|","g",$0)}}' episode_export.txt)
    EPISODE_SUMMARY=$(awk -F"\t" -r -v ep=${episode} '{if ($1==ep) {val= gensub(/\r/,"","g",$7);val=gensub (/\\t/,"\t","g",val); val=gensub(/\\n/,"\n","g",val); print val}}' episode_export.txt|perl -Mopen=locale -pe 's/&#x([\da-f]+);/chr hex $1/gie')
    EPISODE_LINKS=$(awk -F"\t" -r -v ep=${episode} '{if ($1==ep) {val= gensub(/\r/,"","g",$8);val=gensub (/\\t/,"\t","g",val); val=gensub(/\\n/,"\n","g",val); print val}}' episode_export.txt)
}

function update_ep_image_SQL () {
    source .env
    if [ -z $"SSH_CMD" ] || [ -z $"MYSQL_DB" ] || [ -z "MYSQL_USER" ] || [ -z "MYSQL_PASSWORD" ]|| [ -z "MYSQL_PREFIX" ]; then
	echo 'Please set the variables "SSH_CMD", "MYSQL_DB", "MYSQL_USER", "MYSQL_PASSWORD", "MYSQL_PREFIX" in the .env file next to this script'
	exit
    fi

    MYSQL_CMD="${SSH_CMD} mysql ${MYSQL_DB} -u${MYSQL_USER} -p${MYSQL_PASSWORD} -B"
    ${MYSQL_CMD} << EOM
EOM
}

function mktemp_jpg () {
    local fn="$(mktemp)"
    mv ${fn} ${fn}.jpg
    echo "${fn}.jpg"
}

function get_overlay_logo() {
    local logo="$(mktemp_jpg)"
    convert \
        -background '#1115' ${LOGO} -resize 150x150 -gravity center -extent 200x200 \
        ${logo}
    echo ${logo}
}

function get_overlay_text() {
    local text="$(mktemp_jpg)"
    local pd="$(echo $EPISODE_POST_DATE|cut -d'T' -f1)"
    local label="${PODCAST_TITLE}\n${EPISODE} - ${EPISODE_TITLE}\n(${pd})"
    convert \
          -background 'transparent' -fill 'white' ${FONT} -pointsize 20 -gravity center -size 300x100 caption:"${label}" -background '#1115' -extent 350x150 \
          ${text}
    echo ${text}
}

function get_temp_image() {
    local image="$1"
    local episode_tmp="$(mktemp)"
    curl -L "$image" >$episode_tmp 2>/dev/null
    local ext=$(file /data/podcast/podcast/zartosztaly-new.jpg --extension|cut -d: -f2|cut -d/ -f1|tr -d " ")
    mv "${episode_tmp}" "${episode_tmp}.${ext}"
    echo "${episode_tmp}.${ext}"
}

function get_overlay_image() {
    local logo="$(mktemp_jpg)"
    local overlay_text="$(get_overlay_text)"
    if [ "${EPISODE_IMAGE}" = "NULL" ]; then
        convert ${LOGO} -resize 950x650 -gravity north -background black -extent 1280x720 \
          miff:- |
            composite \
                -compose src_over -gravity northeast -geometry +50+50 ${FONT} "${overlay_text}" \
                - \
                ${logo}
    else
        local overlay_logo="$(get_overlay_logo)"

        convert "${EPISODE_IMAGE}" -resize 950x600 -gravity north -background black -extent 1280x720 \
          miff:- |
             composite \
                -compose src_over -gravity northwest -geometry +20+20 "${overlay_logo}" \
                - \
          miff:- |
            composite \
                -compose src_over -gravity northeast -geometry +20+20 "${overlay_text}" \
                - \
                ${logo}
        rm ${overlay_logo}
    fi
    rm ${overlay_text}
    echo ${logo}
}

function create_cover_art() {
    echo "Creating cover art title: ${text}" >&2
    local target="${TARGET_DIR}/${EPISODE_SLUG}_cover.jpg"
    local pd=$(echo $EPISODE_POST_DATE|cut -d'T' -f1)
    if [ "${EPISODE_IMAGE}" = "NULL" ]; then
        convert ${LOGO} -resize 2200x1600 -gravity center -background black -extent 2400x2400 \
	    miff:- \
        | convert - -gravity north ${FONT} -pointsize 140 -fill white -annotate +0+50 "$PODCAST_TITLE" \
	    miff:- \
        | convert - -gravity north ${FONT} -pointsize 100 -fill white -annotate +0+200 "$EPISODE - $EPISODE_TITLE" \
	    miff:- \
        | convert - -gravity southwest ${FONT} -pointsize 100 -fill white -annotate +50+50 "${pd}" \
       	    "${target}"
    else
    	local overlay_logo="$(mktemp_jpg)"
        convert \
            -background '#1115' ${LOGO} -resize 700x700 -gravity center -extent 800x800 \
            ${overlay_logo}
        convert "${EPISODE_IMAGE}" -resize 2200x1600 -gravity center -background black -extent 2400x2400 \
          miff:- \
        | composite -compose src_over -gravity southeast -geometry +40+40 "${overlay_logo}" - \
	    miff:- \
        | convert - -gravity north ${FONT} -pointsize 140 -fill white -annotate +0+50 "$PODCAST_TITLE" \
	    miff:- \
        | convert - -gravity north ${FONT} -pointsize 100 -fill white -annotate +0+200 "$EPISODE - $EPISODE_TITLE" \
	    miff:- \
        | convert - -gravity southwest ${FONT} -pointsize 100 -fill white -annotate +50+50 "${pd}" \
       	    "${target}"
       rm ${overlay_logo}
    fi
}

function create_chapter_frame() {
    local last_frame="$1"
    local text="$2"
    local image="$3"
    echo "Creating chapter frame title: ${text} image: ${image}" >&2
    local frame="$(mktemp_jpg)"
    local angle=$(( $RANDOM %30 - 15 ))
    if [ -z "${image}" ]; then
        local xoff=$(( $RANDOM % 360 - 180 ));  [ -z $(echo $xoff|grep '-') ] && xoff='+'$xoff
        local yoff=$(( $RANDOM % 780 - 450 )); [ -z $(echo $yoff|grep '-') ] && yoff='+'$yoff
	convert -background khaki -border 1 -bordercolor gray -size 720x210 \
		-gravity center ${FONT} -pointsize 60 -fill black caption:"${text}" \
		-background transparent -rotate ${angle} miff:- | \
	    composite -compose src_over -gravity center - -geometry ${xoff}${yoff} \( "${last_frame}" -resize 1500x1500 \) \
		${frame}
    else
        local xoff=$(( $RANDOM % 360 - 180 ));  [ -z $(echo $xoff|grep '-') ] && xoff='+'$xoff
        local yoff=$(( $RANDOM % 240 - 120 )); [ -z $(echo $yoff|grep '-') ] && yoff='+'$yoff
        convert xc:white -resize 720x480 -size 720x210 -fill black ${FONT} -pointsize 60 -gravity center caption:"$text" -append  miff:- | \
            composite -compose src_over -gravity north \( ${image} -resize 720x480 \) - miff:- | \
            convert - -bordercolor Snow -background gray50 -polaroid ${angle} miff:- | \
            composite -compose src_over -gravity center - -geometry ${xoff}${yoff} \( "${last_frame}" -resize 1500x1500 \)  \
             ${frame}
    fi
    echo ${frame}
}

function create_title_frame() {
    local ep_frame="$1"
    local text="$2"

    local frame="$(mktemp_jpg)"
    convert ${ep_frame} -background black -gravity south ${FONT} -pointsize 30 -interline-spacing -5 -fill white -annotate +0+15 "${text}" ${frame}
    echo ${frame}
}

function add_episode_frame() {
    local script="$1"
    local duration="$2"
    local last_frame="$3"
    local text="$4"
    local image="$5"

    echo "Creating frame in ${script} with duration ${duration} title: ${text} image: ${image}" >&2
    local frame="$(mktemp_jpg)"
    local angle=$(( $RANDOM % 30 - 15 ))
    if [ -z "${image}" ]; then
        local xoff=$(( $RANDOM % 160 - 80 ));  [ -z $(echo $xoff|grep '-') ] && xoff='+'$xoff
        local yoff=$(( $RANDOM % 300 - 150 )); [ -z $(echo $yoff|grep '-') ] && yoff='+'$yoff
	convert -background khaki -border 1 -bordercolor gray -size 450x150 \
		-gravity center ${FONT} -pointsize 25 -fill black caption:"${text}" \
		-background transparent -rotate ${angle} miff:- | \
	    composite -compose src_over -gravity center - -geometry ${xoff}${yoff} "${last_frame}" \
		${frame}
    else
        local xoff=$(( $RANDOM % 160 - 80 ));  [ -z $(echo $xoff|grep '-') ] && xoff='+'$xoff
        local yoff=$(( $RANDOM % 100 - 50 )); [ -z $(echo $yoff|grep '-') ] && yoff='+'$yoff
        convert xc:white -resize 450x350 -size 450x120 -fill black ${FONT} -pointsize 25 -gravity center caption:"$text" -append  miff:- | \
            composite -compose src_over -gravity north \( ${image} -resize 450x350  \) - miff:- | \
            convert - -bordercolor Snow -background gray50 -polaroid ${angle} miff:- | \
            composite -compose src_over -gravity center - -geometry ${xoff}${yoff} "${last_frame}"  \
             ${frame}
    fi
    [ -z "${duration}" ] || echo "duration ${duration}.00" >>$script
    echo "file ${frame}" >>$script
    echo ${frame}
}

# Will create a temporary script and store the name in the global "SCRIPT" variable
function create_images () {
    echo "Processing: ${EPISODE_SLUG}"

    echo "Generating logo with text ${EPISODE_TITLE}"
    local skip_video_frames=$1
    local skip_image_frames=$2
    local last_chapter_frame="${TARGET_DIR}/${EPISODE_SLUG}_cover.jpg"
    local position=0
    local last_position=2
    local pd="$(echo $EPISODE_POST_DATE|cut -d'T' -f1)"

    mkdir -p "${TARGET_DIR}/images/${EPISODE_SLUG}/"

    #Create video background frame and title overlay
    if [ ! "${skip_video_frames}" = "true" ]; then
	SCRIPT=$(mktemp)
	echo "Adding title frame in ${SCRIPT} title: ${text}" >&2
    	local overlay_frame=$(get_overlay_image)
      	local title_frame=$(create_title_frame "$overlay_frame" "$PODCAST_TITLE\n$EPISODE - $EPISODE_TITLE\n(${pd})")
      	cp ${title_frame} "${TARGET_DIR}/${EPISODE_SLUG}_title.jpg"
	local last_video_frame="$overlay_frame"
	echo "ffconcat version 1.0

file ${title_frame}" > ${SCRIPT}
    fi

    local psc_in="${SRC_DIR}/${EPISODE_SLUG}.psc"
    local psc_out="${TARGET_DIR}/${EPISODE_SLUG}.psc"
    local last_title=""
    echo '<psc:chapters xmlns:psc="http://podlove.org/simple-chapters" version="1.2">' >"${psc_out}"
    while IFS= read -r line || [ -z "${done_last}" ] ; do
	[ -z "$line" ] && local done_last=1
	k="$(echo $line|cut -d= -f1)"
	v="$(echo $line|cut -d= -f2-|cut -c2-|rev|cut -c2-|rev)"
	case "$k" in
	    "title" )
		if [ -z "$last_title" ]; then
		    last_title=$v;
		fi
		;;
	    "start" )
		local position_raw=$v
		local position="$(expr $(echo $v|cut -c 1-2) \* 3600 + $(echo $v|cut -c 4-5) \* 60 + $(echo $v|cut -c 7-8))"
		;;
	    "image" )
		local image="$(echo $v |perl -C -MHTML::Entities -pe 'decode_entities($_);')"
		;;
	    "href" )
		local href="$(echo $v |perl -C -MHTML::Entities -pe 'decode_entities($_);')"
		;;
	esac
	if ( [ "$k" = "title" ] && [ "${last_title}" != "${v}" ] ) || [ ! -z "${done_last}" ]; then
		    local duration=$(( $position - $last_position ))
		    if [ ! "${skip_image_frames}" = "true" ]; then 
		    	mv $(create_chapter_frame "${last_chapter_frame}" "${last_title}" "${image}") "${TARGET_DIR}/images/${EPISODE_SLUG}/${EPISODE_SLUG}_${position}.jpg"
		    	local last_chapter_frame="${TARGET_DIR}/images/${EPISODE_SLUG}/${EPISODE_SLUG}_${position}.jpg"
		    fi
		    echo "	<psc:chapter title='${last_title}' start='${position_raw}' " \
			"image='${CDN_BASE_URL}/images/${EPISODE_SLUG}/${EPISODE_SLUG}_${position}.jpg'" \
			$([ ! -z "$href" ] && echo "href='$(echo $href|perl -C -MHTML::Entities -pe 'encode_entities($_);')'") \
			"/>" >> "${psc_out}"
		    if [ ! "${skip_video_frames}" = "true" ]; then 
			    last_video_frame=$(add_episode_frame "$SCRIPT" "$duration" "$last_video_frame" "$last_title" "$image")
		    fi
		    local last_position=$position
		    local href=""
		    local image=""
		    local last_title="$(echo $v |perl -C -MHTML::Entities -pe 'decode_entities($_);')"
	fi
    done <<< $( xpath -q -e '//@title|//@start|//@image|//@href' "${psc_in}" )
    echo '</psc:chapters>' >>"${psc_out}"

    # resize frames to 3000x3000 for Apple using low quality JPG for size
    mogrify -quality 20 -resize 3000x3000 "${TARGET_DIR}/images/${EPISODE_SLUG}/${EPISODE_SLUG}_*.jpg"

    if [ ! "${skip_video_frames}" = "true" ]; then
	local mp3src="${TARGET_DIR}/${EPISODE_SLUG}.mp3"
	local position=$(ffprobe -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "${mp3src}" 2>/dev/null |cut -d\. -f1)
	local duration=$(( $position - $last_position ))
	echo "duration ${duration}.00" >>$SCRIPT
	echo "file ${last_video_frame}" >>$SCRIPT
	# Remove overlay if there are other frames in the video
	[ "${overlay_frame}" == "${last_video_frame}" ] ||  rm "$overlay_frame"
    fi
}

function create_video () {
    local sequence="$1"
    local mp3src="${TARGET_DIR}/${EPISODE_SLUG}.mp3"
    local src_params="-hide_banner -y -f concat -safe 0 -i ${sequence}"
    local video_out_params="-c:v h264 -preset fast -tune stillimage -profile:v high -pix_fmt yuvj420p -fps_mode vfr -vf fps=20 -b:v 3500K -async 1"
    local audio_out_params="-ac 2 -c:a aac -b:a 192K"
#    local audio_out_params="-ac 2 -c:a copy"
    ffmpeg ${src_params} ${video_out_params} -pass 1 -an -f mp4 /dev/null && \
	ffmpeg ${src_params} -i ${mp3src} -shortest ${video_out_params} -pass 2 ${audio_out_params} "${TARGET_DIR}/${EPISODE_SLUG}.mp4"
#    ffmpeg ${src_params} -i ${mp3src} -shortest ${video_out_params} ${audio_out_params} "${TARGET_DIR}/${EPISODE_SLUG}.mp4"
}

function remove_images () {
    echo removing images from $1
    grep file $1|cut -d\  -f2|sort -u|xargs rm
    rm $1
}

function add_mp3cover () {
    local lowqual="$(mktemp_jpg)"
    convert "${TARGET_DIR}/${EPISODE_SLUG}_cover.jpg" -quality 20 -resize 3000x3000 "${lowqual}"
    eyeD3 --remove-all-images \
      -a "${PODCAST_TITLE}" \
      -t "${EPISODE_TITLE}" \
      -n ${EPISODE} \
      --recording-date ${EPISODE_REC_DATE} \
      --release-date ${EPISODE_POST_DATE} \
      --add-image "${lowqual}:MEDIA" \
      "${TARGET_DIR}/${EPISODE_SLUG}".mp3
    rm $lowqual
}

function display_template () {
    local EPISODE_RECORDED="$(echo $EPISODE_REC_DATE|cut -d'T' -f1)"
    local EPISODE_POSTED="$(echo $EPISODE_POST_DATE|cut -d'T' -f1)"
    local EPISODE_HASHKEYS="$(echo "${EPISODE_KEYWORDS}"|awk -r '{print "#" gensub(/,/,", #","g",gensub(/ /,"","g",$0))}')"
    eval "echo \"$(cat display_template.txt)\""
}

function usage () {
	echo "
Specify the episode to regenerate.
	generate_video.sh [episode] [-h] [-f] [-e <episode>]
	-h display this help
	-f force regeneration
	-i generate images only
	-v generate video only
	-e episode number (overrides positional argument)
"
}

while getopts hfive: flag
do
	case "${flag}" in
		h) usage; exit 0;;
		f) FORCE="true";;
		i) IMAGEONLY="true";;
		v) VIDEOONLY="true";;
		e) EPISODE=${OPTARG};;
	esac
done
shift $((OPTIND-1))

[ -z "${EPISODE}" ] && EPISODE=$1

if [ -z "${EPISODE}" ]; then
	usage
	exit 1
fi

[ -e "${TARGET_DIR}" ] || mkdir -p "${TARGET_DIR}"
[ -e "${TARGET_DIR}/images" ] || mkdir -p "${TARGET_DIR}/images"

if [ ! -z "${FORCE}" ]; then rm episode_export.txt; fi
load_ep_data_SQL $EPISODE

if [ "${EPISODE_SLUG}" = "" ]; then
    echo "Episode is missing in DB"
    exit
fi
if [ "${EPISODE_SLUG}" = "NULL" ]; then
    echo "Episode has no slug set in DB, have you saved the episode yet?"
    exit
fi
if [ ! -e "${SRC_DIR}/${EPISODE_SLUG}.psc" ]; then
    echo "Episode psc is missing, cannot generate images"
    exit
fi
if [ -e "${SRC_DIR}/${EPISODE_SLUG}.png" ]; then EPISODE_IMAGE="${SRC_DIR}/${EPISODE_SLUG}.png"
elif [ -e "${SRC_DIR}/${EPISODE_SLUG}.jpg" ] ; then EPISODE_IMAGE="${SRC_DIR}/${EPISODE_SLUG}.jpg"
elif [ -e "${SRC_DIR}/${EPISODE_SLUG}.jpeg" ] ; then EPISODE_IMAGE="${SRC_DIR}/${EPISODE_SLUG}.jpeg"
else
    echo "Episode cover image is missing, cannot generate images for episode ${EPISODE_SLUG}"
    exit
fi

if [ ! -z "${FORCE}" ]; then
	echo "Forcing regeneration of episode ${EPISODE}"
	if [ ! "${VIDEOONLY}" = "true" ]; then
		rm "${TARGET_DIR}/${EPISODE_SLUG}"_cover.jpg
		rm -rf "${TARGET_DIR}/images/${EPISODE_SLUG}"
	fi
	if [ ! "${IMAGEONLY}" = "true" ]; then
	     rm "${TARGET_DIR}/${EPISODE_SLUG}".mp4
	fi
fi
if [ -z "${EPISODE_TITLE}" ]; then
	echo "Error loading episode data" >&2
	exit;
fi
if [ ! "${VIDEOONLY}" = "true" ] && [ ! -e "${TARGET_DIR}/${EPISODE_SLUG}_cover.jpg" ]; then
  create_cover_art
  add_mp3cover
fi
if [ ! -e "${TARGET_DIR}/${EPISODE_SLUG}.mp4" ] || [ ! -d "${TARGET_DIR}/images/${EPISODE_SLUG}" ]; then
	create_images "${IMAGEONLY}" "${VIDEOONLY}"
fi
if [ ! "${IMAGEONLY}" = "true" ] && [ ! -e "${TARGET_DIR}/${EPISODE_SLUG}.mp4" ]; then
  if [ -e "$SCRIPT" ]; then
      create_video $SCRIPT
      tree -H "/podcast" -L 1 --noreport --charset utf-8 -P "*.mp?" -o ${TARGET_DIR}/index.html ${TARGET_DIR}
      remove_images "${SCRIPT}"
  fi
fi

chown www-data:www-data -R ${TARGET_DIR}
chmod -R ug+rwX ${TARGET_DIR}
display_template
