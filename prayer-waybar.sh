#!/bin/bash
# ── Config ───────────────────────────────────────────────────────────────────
readonly LAT="30.0444"
readonly LNG="31.2357"
readonly TZ="Africa/Cairo"
readonly AUTH="Egypt"
readonly CACHE_DIR="$HOME/.cache/waybar-prayer"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly MUSIC_DIR="$SCRIPT_DIR/PrayerNotify"
# ── Daylight Saving Time offset ──────────────────────────────────────────────
# Set to 1 to add one hour to all prayer times, 0 to disable
readonly DST_OFFSET=0

readonly TODAY=$(date +%Y-%m-%d)
readonly TOMORROW=$(date -d tomorrow +%Y-%m-%d)

readonly CACHE_FILE="$CACHE_DIR/prayer_${TODAY}.json"
readonly TOMORROW_CACHE="$CACHE_DIR/prayer_${TOMORROW}.json"

mkdir -p "$CACHE_DIR"

# ── Arabic names & MP3 map ───────────────────────────────────────────────────
declare -A AR=([fajr]="الفجر" [dhuhr]="الظهر" [asr]="العصر" [maghrib]="المغرب" [isha]="العشاء")

# If today is Friday, override dhuhr label
if [[ $(date +%u) -eq 5 ]]; then
  AR[dhuhr]="الجمعة"
fi
declare -A MP3=([fajr]="1.mp3" [dhuhr]="2.mp3" [asr]="3.mp3" [maghrib]="4.mp3" [isha]="5.mp3")

# ── Helpers ──────────────────────────────────────────────────────────────────
die() {
  echo '{"text":"🕌 خطأ","tooltip":"'"$1"'","class":"error"}'
  exit 1
}

to12h() {
  local h="${1%%:*}" m="${1##*:}"
  local n=$((10#$h)) suffix="ص"
  ((n >= 12)) && suffix="م"
  ((n > 12)) && ((n -= 12))
  ((n == 0)) && n=12
  printf "%d:%02d %s" "$n" "$((10#$m))" "$suffix"
}

# Convert HH:MM to minutes since midnight
to_mins() {
  local h="${1%%:*}" m="${1##*:}"
  echo $((10#$h * 60 + 10#$m))
}

# Apply DST offset to a HH:MM string → returns adjusted HH:MM
apply_dst() {
  local h="${1%%:*}" m="${1##*:}"
  local total=$((10#$h * 60 + 10#$m + DST_OFFSET * 60))
  # wrap within 0–1439
  total=$(((total % 1440 + 1440) % 1440))
  printf "%02d:%02d" $((total / 60)) $((total % 60))
}

fetch_prayers() {
  local date_arg="$1" out
  local args=(coord --lat "$LAT" --lng "$LNG" -t "$TZ" --auth "$AUTH" --format "%H:%M")
  [[ -n "$date_arg" ]] && args+=(--date "$date_arg")
  args+=(fajr dhuhr asr maghrib isha)
  for _ in {1..5}; do
    out=$(salah_cli "${args[@]}" 2>/dev/null)
    [[ -n "$out" ]] && {
      echo "$out"
      return 0
    }
    sleep 2
  done
  return 1
}

fetch_hijri() { hijri-date 2>/dev/null; }

play_adhan() {
  local f="$1"
  [[ -f "$f" ]] || return 1
  if command -v mpv &>/dev/null; then
    setsid mpv --no-video --really-quiet --audio-device=auto \
      --no-resume-playback --no-save-position-on-quit \
      "$f" </dev/null &>/dev/null &
  elif command -v ffplay &>/dev/null; then
    setsid ffplay -nodisp -autoexit -loglevel quiet "$f" </dev/null &>/dev/null &
  elif command -v paplay &>/dev/null; then
    setsid paplay "$f" </dev/null &>/dev/null &
  else
    return 1
  fi
  disown
  return 0
}

hijri_to_ar() {
  local raw="$1"
  local day month_en month_extra year month_ar
  day=$(awk '{print $1}' <<<"$raw")
  month_en=$(awk '{print $2}' <<<"$raw")
  month_extra=$(awk '{print $3}' <<<"$raw")
  year=$(awk '{print $4}' <<<"$raw" | cut -d- -f1)

  case "$month_en" in
  Muharram) month_ar="مُحَرَّم" ;;
  Safar) month_ar="صَفَر" ;;
  Rabi*)
    if grep -qi "awwal\|first\|al-a" <<<"$month_extra"; then
      month_ar="رَبِيع الأوَّل"
    else
      month_ar="رَبِيع الثَّانِي"
    fi
    ;;
  Jumada*)
    if grep -qi "awwal\|first\|al-a" <<<"$month_extra"; then
      month_ar="جُمَادَى الأُولَى"
    else
      month_ar="جُمَادَى الآخِرَة"
    fi
    ;;
  Rajab) month_ar="رَجَب" ;;
  Shawwal) month_ar="شَوَّال" ;;
  Sha*) month_ar="شَعْبَان" ;;
  Ramadan) month_ar="رَمَضَان" ;;
  Dhu*)
    if grep -qi "qi\|qa\|qaa\|q'" <<<"$month_extra"; then
      month_ar="ذُو القَعْدَة"
    else
      month_ar="ذُو الحِجَّة"
    fi
    ;;
  *) month_ar="$month_en" ;;
  esac

  echo "${day} ${month_ar} ${year}"
}

# ── Purge yesterday's and older cache files ───────────────────────────────────
# Delete any prayer_*.json that is NOT today's or tomorrow's file.
# This ensures stale files are cleaned up on each new day,
# and hijri-date (today-only) is always re-fetched fresh.
find "$CACHE_DIR" -maxdepth 1 -name "prayer_*.json" | while read -r f; do
  base=$(basename "$f" .json) # prayer_YYYY-MM-DD
  file_date="${base#prayer_}"
  if [[ "$file_date" != "$TODAY" && "$file_date" != "$TOMORROW" ]]; then
    rm -f "$f"
  fi
done
find "$CACHE_DIR" -maxdepth 1 -name "notified_*" -mtime +1 -delete 2>/dev/null

# ── Build today's cache ──────────────────────────────────────────────────────
if [[ ! -f "$CACHE_FILE" ]]; then
  raw=$(fetch_prayers) || die "salah_cli failed"
  # hijri-date only gives today — capture and convert now
  hijri_raw=$(fetch_hijri)
  hijri=$(hijri_to_ar "$hijri_raw")
  {
    echo "hijri=${hijri}"
    echo "$raw"
  } >"$CACHE_FILE"
fi

# ── Build tomorrow's cache ───────────────────────────────────────────────────
if [[ ! -f "$TOMORROW_CACHE" ]]; then
  raw=$(fetch_prayers "$TOMORROW")
  # hijri-date can't give tomorrow's date — leave blank
  [[ -n "$raw" ]] && {
    echo "hijri="
    echo "$raw"
  } >"$TOMORROW_CACHE"
fi

# ── Load today's data ────────────────────────────────────────────────────────
hijri_formatted=$(grep "^hijri=" "$CACHE_FILE" | cut -d= -f2-)
prayers_raw=$(grep -v "^hijri=" "$CACHE_FILE")

# ── Apply DST offset to all prayer times ─────────────────────────────────────
if ((DST_OFFSET != 0)); then
  prayers=$(while read -r name time; do
    echo "$name $(apply_dst "$time")"
  done <<<"$prayers_raw")
else
  prayers="$prayers_raw"
fi

# ── Current time in minutes ──────────────────────────────────────────────────
now_mins=$(date "+%H*60+%M" | bc)

# ── Find previous and next prayer ───────────────────────────────────────────
prev_name="" prev_mins=0
next_name="" next_mins=0

while read -r name time; do
  t=$(to_mins "$time")
  if ((t > now_mins)); then
    next_name="$name"
    next_mins=$t
    break
  fi
  prev_name="$name"
  prev_mins=$t
done <<<"$prayers"

# ── After isha: wrap to tomorrow's fajr ─────────────────────────────────────
if [[ -z "$next_name" ]]; then
  next_name="fajr"
  if [[ -f "$TOMORROW_CACHE" ]]; then
    fajr_raw=$(grep -v "^hijri=" "$TOMORROW_CACHE" | head -1 | awk '{print $2}')
    fajr_time=$(apply_dst "$fajr_raw")
  else
    fajr_time="05:00"
  fi
  next_mins=$(($(to_mins "$fajr_time") + 1440))
fi

# ── Minutes since last prayer (guard: before fajr → 999) ────────────────────
if [[ -n "$prev_name" ]]; then
  mins_since_prev=$((now_mins - prev_mins))
else
  mins_since_prev=999
fi

# ── Countdown ────────────────────────────────────────────────────────────────
diff=$((next_mins - now_mins))
hh=$((diff / 60))
mm=$((diff % 60))
((hh > 0)) && timestr="${hh}س ${mm}د" || timestr="${mm}د"

# ── 15-minute adhan notification (lockfile-based, race-safe) ─────────────────
if ((diff > 0 && diff <= 15)); then
  lock="$CACHE_DIR/notified_${TODAY}_${next_name}"
  if [[ ! -f "$lock" ]]; then
    touch "$lock"
    play_adhan "$MUSIC_DIR/${MP3[$next_name]}"
  fi
fi

# ── Tooltip ──────────────────────────────────────────────────────────────────
tooltip="🗓 ${hijri_formatted}\n"
while read -r name time; do
  tooltip+="${AR[$name]} $(to12h "$time")\n"
done <<<"$prayers"

# ── CSS class ────────────────────────────────────────────────────────────────
if ((mins_since_prev <= 10)); then
  class="just-passed"
elif ((diff <= 15)); then
  class="urgent"
else
  class="normal"
fi

# ── Output ───────────────────────────────────────────────────────────────────
printf '{"text":"🕌 %s بعد %s","tooltip":"%s","class":"%s"}\n' \
  "${AR[$next_name]}" "$timestr" "$tooltip" "$class"
