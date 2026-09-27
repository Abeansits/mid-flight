# shellcheck shell=bash

aspect_codex_size() {
  case "$1" in
    1:1) printf '%s\n' "1024x1024" ;;
    16:9) printf '%s\n' "1536x864" ;;
    9:16) printf '%s\n' "864x1536" ;;
    3:2) printf '%s\n' "1536x1024" ;;
    2:3) printf '%s\n' "1024x1536" ;;
  esac
}

write_media_prompt() {
  local media_prompt_file="$1"
  local media_prompt refs_file ref ref_index

  if [ "$MODE" = "image-gen" ]; then
    media_prompt="$IMAGE_GEN_PROMPT"
  else
    media_prompt="$VIDEO_GEN_PROMPT"
  fi

  {
    printf '%s\n' "$media_prompt"
    if [ -n "$ASPECT" ]; then
      printf '\nAspect ratio: %s\n' "$ASPECT"
      if [ "$MODE" = "image-gen" ]; then
        printf 'Codex size: %s\n' "$(aspect_codex_size "$ASPECT")"
      elif [ "${#REFS[@]}" -gt 0 ]; then
        printf '%s\n' "The opening frame already exists. Do not pass aspect_ratio to image_to_video."
      else
        printf '%s\n' "Set this ratio on the source still with image_gen. Do not pass aspect_ratio to image_to_video."
      fi
    fi
    if [ "${#REFS[@]}" -gt 0 ]; then
      printf '\nReference images:\n'
      ref_index=0
      for ref in "${REFS[@]}"; do
        if [ "$MODE" = "video-gen" ] && [ "$ref_index" -eq 0 ]; then
          printf -- '- opening frame: %s\n' "$ref"
        else
          printf -- '- %s\n' "$ref"
        fi
        ref_index=$((ref_index + 1))
      done
    fi
  } > "$media_prompt_file"
  if [ "${#REFS[@]}" -gt 0 ]; then
    refs_file="$WORKDIR/media-refs.txt"
    printf '%s\n' "${REFS[@]}" > "$refs_file"
    export MIDFLIGHT_REFS_FILE="$refs_file"
  fi
}

resolve_existing_path() {
  local target="$1" dir base
  dir="$(cd -P "$(dirname "$target")" && pwd)"
  base="$(basename "$target")"
  printf '%s\n' "$dir/$base"
}

strip_path_punctuation() {
  local candidate="$1" lastchar
  while [ -n "$candidate" ]; do
    lastchar="${candidate#"${candidate%?}"}"
    case "$lastchar" in
      "."|","|":"|";") candidate="${candidate%?}" ;;
      *) break ;;
    esac
  done
  printf '%s\n' "$candidate"
}

written_since_gen_stamp() {
  local file="$1"
  if [ -z "${GEN_STAMP:-}" ] || [ ! -f "$GEN_STAMP" ] || [ ! -f "$file" ]; then
    return 1
  fi
  if [ "$file" -ef "$GEN_STAMP" ]; then
    return 1
  fi
  [ "$file" -nt "$GEN_STAMP" ]
}

last_written_path() {
  local text="$1" i len rest candidate found=""
  case "$text" in
    \"*\") text="${text#\"}"; text="${text%\"}" ;;
    \'*\') text="${text#\'}"; text="${text%\'}" ;;
  esac
  len=${#text}
  i=0
  while [ "$i" -lt "$len" ]; do
    rest="${text:$i}"
    case "$rest" in
      /*)
        candidate="$rest"
        while [ -n "$candidate" ]; do
          candidate="$(strip_path_punctuation "$candidate")"
          case "$candidate" in
            *\"|*\') candidate="${candidate%?}"; continue ;;
          esac
          if written_since_gen_stamp "$candidate"; then
            found="$candidate"
            break
          fi
          candidate="${candidate%?}"
        done
        ;;
    esac
    i=$((i + 1))
  done
  printf '%s\n' "$found"
}

is_video_file() {
  local base
  base="$(basename "$1")"
  case "$base" in
    *.mp4|*.MP4|*.mov|*.MOV|*.webm|*.WEBM|*.m4v|*.M4V|*.mkv|*.MKV) return 0 ;;
    *) return 1 ;;
  esac
}

is_reference_file() {
  local candidate="$1" ref
  [ "${#REFS[@]}" -gt 0 ] || return 1
  for ref in "${REFS[@]}"; do
    if [ "$candidate" -ef "$ref" ]; then
      return 0
    fi
  done
  return 1
}

last_written_video_path() {
  local text="$1" i len rest candidate found=""
  case "$text" in
    \"*\") text="${text#\"}"; text="${text%\"}" ;;
    \'*\') text="${text#\'}"; text="${text%\'}" ;;
  esac
  len=${#text}
  i=0
  while [ "$i" -lt "$len" ]; do
    rest="${text:$i}"
    case "$rest" in
      /*)
        candidate="$rest"
        while [ -n "$candidate" ]; do
          candidate="$(strip_path_punctuation "$candidate")"
          case "$candidate" in
            *\"|*\') candidate="${candidate%?}"; continue ;;
          esac
          if written_since_gen_stamp "$candidate" && is_video_file "$candidate" && ! is_reference_file "$candidate"; then
            found="$candidate"
            break
          fi
          candidate="${candidate%?}"
        done
        ;;
    esac
    i=$((i + 1))
  done
  if [ -n "$found" ]; then
    resolve_existing_path "$found"
    return 0
  fi
  return 1
}

canonicalize_image_output() {
  local body="$1" trimmed found
  trimmed="${body%"${body##*[![:space:]]}"}"
  trimmed="${trimmed#"${trimmed%%[![:space:]]*}"}"
  if [ -n "$trimmed" ] && written_since_gen_stamp "$trimmed"; then
    resolve_existing_path "$trimmed"
    return 0
  fi
  found="$(last_written_path "$trimmed")"
  if [ -n "$found" ]; then
    resolve_existing_path "$found"
    return 0
  fi
  return 1
}
