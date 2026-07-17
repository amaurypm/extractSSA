#!/bin/bash

if [ "$#" -eq 0 ]; then
    echo "Usage: $0 <video1> [video2 ...]"
    exit 1
fi

for file in "$@"; do
    if [ ! -f "$file" ]; then
        echo "Skipping missing file: $file"
        echo "--------------------------------------"
        continue
    fi

    echo "Processing: $file"
    basename="${file%.*}"

    # Get subtitle stream indices
    mapfile -t sub_indices < <(ffprobe -v error \
        -select_streams s \
        -show_entries stream=index \
        -of csv=p=0 "$file")

    if [ ${#sub_indices[@]} -eq 0 ]; then
        echo "No subtitles found in: $file"
        echo "--------------------------------------"
        continue
    fi

    declare -A name_counts

    # Loop by subtitle stream position
    # ffmpeg map 0:s:N uses subtitle-relative indices
    for ((track_idx=0; track_idx<${#sub_indices[@]}; track_idx++)); do
        codec=$(ffprobe -v error \
            -select_streams "s:${track_idx}" \
            -show_entries stream=codec_name \
            -of default=nw=1:nk=1 "$file")

        # Only process ASS/SSA subtitles
        if [[ "$codec" != "ass" && "$codec" != "ssa" ]]; then
            echo "-> Skipping subtitle stream $track_idx (codec: $codec)"
            continue
        fi

        lang=$(ffprobe -v error \
            -select_streams "s:${track_idx}" \
            -show_entries stream_tags=language \
            -of default=nw=1:nk=1 "$file")

        title=$(ffprobe -v error \
            -select_streams "s:${track_idx}" \
            -show_entries stream_tags=title \
            -of default=nw=1:nk=1 "$file")

        # Default language tag
        if [ -z "$lang" ]; then
            lang="und"
        fi

        # Use subtitle title if available
        if [ -n "$title" ]; then
            safe_title=$(printf '%s' "$title" | sed 's/[^[:alnum:]._-]/_/g')
            base_out="${basename}.${lang}.${safe_title}"
        else
            base_out="${basename}.${lang}"
        fi

        # Avoid overwriting duplicate language/title combinations
        count=${name_counts["$base_out"]:-0}
        if [ "$count" -eq 0 ]; then
            outfile="${base_out}.srt"
        else
            outfile="${base_out}.$((count + 1)).srt"
        fi
        name_counts["$base_out"]=$((count + 1))

        # Extra safety if file already exists
        n=${name_counts["$base_out"]}
        while [ -e "$outfile" ]; do
            ((n++))
            outfile="${base_out}.${n}.srt"
        done
        name_counts["$base_out"]=$n

        echo "-> Extracting subtitle stream $track_idx (codec: $codec, lang: $lang) to: $outfile"
        

        ffmpeg -y -v error -i "$file" -map "0:s:${track_idx}" -f srt - | \
            sed -E '
                s/<font[^>]*>//gI;
                s/<\/font>//gI;
                s/\{[^}]*\}//g
            ' > "$outfile"
    done

    unset name_counts
    echo "--------------------------------------"
done
