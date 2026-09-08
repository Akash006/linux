#!/bin/bash
#===============================================================================
#  Linux Practical Exam - GRADING SCRIPT
#  Run as root on the exam server (CentOS Stream 10) AFTER the candidate finished.
#
#  Usage:  ./exam_check.sh [candidate-name]
#  A transcript is written to /root/exam-result-<candidate>-<date>.txt
#===============================================================================

EXAM_HOME="/etc/exam"
ENV_FILE="${EXAM_HOME}/exam.env"
EXPECTED="${EXAM_HOME}/expected"
DATA="/exam-data"
PASS_PERCENT=80

CANDIDATE="${1:-candidate}"
REPORT="/root/exam-result-${CANDIDATE}-$(date +%Y%m%d-%H%M).txt"

RED='\033[0;31m'; GRN='\033[0;32m'; YLW='\033[1;33m'; CYA='\033[0;36m'; NC='\033[0m'

if [ "$(id -u)" -ne 0 ]; then
    echo "This script must be run as root."; exit 1
fi
if [ ! -f "$ENV_FILE" ] || [ ! -d "$EXPECTED" ]; then
    echo "ERROR: exam environment not found (${ENV_FILE})."
    echo "       Run exam_setup.sh on this server before grading."
    exit 1
fi
. "$ENV_FILE"

TOTAL=0; EARNED=0
Q_NAME=""; Q_T=0; Q_E=0
declare -a SUMMARY

#------------------------------------------------------------------------------
# Framework
#------------------------------------------------------------------------------
flush_q() {
    if [ -n "$Q_NAME" ]; then
        printf "   ----> %-45s %2d / %2d\n" "$Q_NAME" "$Q_E" "$Q_T"
        SUMMARY+=("$(printf '%-48s %3d / %3d' "$Q_NAME" "$Q_E" "$Q_T")")
    fi
    Q_NAME=""; Q_T=0; Q_E=0
}

question() {
    flush_q
    Q_NAME="$1"
    echo
    echo -e "${CYA}== $1 ==${NC}"
}

check() {   # check "<description>" <points> "<shell test>"
    local desc="$1" pts="$2" cmd="$3"
    TOTAL=$((TOTAL + pts)); Q_T=$((Q_T + pts))
    if eval "$cmd" >/dev/null 2>&1; then
        EARNED=$((EARNED + pts)); Q_E=$((Q_E + pts))
        printf "  [ ${GRN}PASS${NC} ] %2d/%-2d  %s\n" "$pts" "$pts" "$desc"
    else
        printf "  [ ${RED}FAIL${NC} ]  0/%-2d  %s\n" "$pts" "$desc"
    fi
}

#------------------------------------------------------------------------------
# Helper predicates (keeps the check strings simple and quoting-safe)
#------------------------------------------------------------------------------
norm() { sed -e 's/[[:space:]]*$//' -e '/^[[:space:]]*$/d' "$1" 2>/dev/null; }

same_file_content() { [ -s "$1" ] && [ -s "$2" ] && [ "$(norm "$1")" = "$(norm "$2")" ]; }

user_in_group() { id -nG "$1" 2>/dev/null | tr ' ' '\n' | grep -qx "$2"; }

field_passwd() { getent passwd "$1" 2>/dev/null | cut -d: -f"$2"; }

chage_value() {  # chage_value <user> <label>
    chage -l "$1" 2>/dev/null | awk -F: -v k="$2" 'index($0,k){gsub(/[[:space:]]/,"",$2); print $2}'
}

acct_locked() { passwd -S "$1" 2>/dev/null | awk '{print $2}' | grep -qE '^(L|LK)$'; }

mode_of() { stat -c %a "$1" 2>/dev/null; }
owner_of() { stat -c %U "$1" 2>/dev/null; }
group_of() { stat -c %G "$1" 2>/dev/null; }

fstab_has() {   # active (non-comment) fstab line for mountpoint $1
    grep -vE '^[[:space:]]*#' /etc/fstab 2>/dev/null | grep -qE "[[:space:]]$1[[:space:]]"
}

mounted_fstype() { findmnt -no FSTYPE "$1" 2>/dev/null | head -1; }
mounted_source() { findmnt -no SOURCE "$1" 2>/dev/null | head -1; }
mount_size_mb() { df -BM --output=size "$1" 2>/dev/null | tail -1 | tr -dc '0-9'; }

between() { [ -n "$1" ] && [ "$1" -ge "$2" ] && [ "$1" -le "$3" ]; }

lv_size_mb() {
    lvs --noheadings --nosuffix --units m -o lv_size "/dev/$1/$2" 2>/dev/null \
        | tr -d ' ' | cut -d. -f1
}


bigfiles_present() {
    local src base
    [ -n "$(find "$DATA" -type f -size +1M 2>/dev/null)" ] || return 1
    for src in $(find "$DATA" -type f -size +1M 2>/dev/null); do
        base=$(basename "$src")
        [ -f "/opt/reports/bigfiles/${base}" ] || return 1
    done
    return 0
}

bigfiles_modes_ok() {
    local src base
    [ -n "$(find "$DATA" -type f -size +1M 2>/dev/null)" ] || return 1
    for src in $(find "$DATA" -type f -size +1M 2>/dev/null); do
        base=$(basename "$src")
        [ -f "/opt/reports/bigfiles/${base}" ] || return 1
        [ "$(stat -c %a "$src")" = "$(stat -c %a "/opt/reports/bigfiles/${base}")" ] || return 1
    done
    return 0
}

bigfiles_times_ok() {
    local src base
    [ -n "$(find "$DATA" -type f -size +1M 2>/dev/null)" ] || return 1
    for src in $(find "$DATA" -type f -size +1M 2>/dev/null); do
        base=$(basename "$src")
        [ -f "/opt/reports/bigfiles/${base}" ] || return 1
        [ "$(stat -c %Y "$src")" = "$(stat -c %Y "/opt/reports/bigfiles/${base}")" ] || return 1
    done
    return 0
}

ww_list_ok() {
    local student="/opt/reports/world-writable.txt"
    [ -s "$student" ] || return 1
    [ -s "${EXPECTED}/ww.txt" ] || return 1
    [ "$(norm "$student")" = "$(cat "${EXPECTED}/ww.txt")" ]
}

no_empty_files() { [ -d "${DATA}/tmpdir" ] && [ -z "$(find "${DATA}/tmpdir" -type f -empty 2>/dev/null)" ]; }

same_inode() { [ -f "$1" ] && [ -f "$2" ] && [ "$(stat -c %i "$1")" = "$(stat -c %i "$2")" ]; }

log_is_growing() {   # $1 = file, $2 = seconds to wait
    local f="$1" w="$2" a b
    [ -f "$f" ] || return 1
    a=$(stat -c %s "$f"); sleep "$w"; b=$(stat -c %s "$f")
    [ "$b" -gt "$a" ]
}

rogue_stopped() { ! pgrep -f exam-rogue.sh >/dev/null 2>&1; }

sudo_nopasswd() { sudo -l -U "$1" 2>/dev/null | grep -qi 'NOPASSWD.*ALL'; }

alice_umask() { su - alice -c 'umask' 2>/dev/null | tr -d ' ' | grep -qx '0027'; }

umask_persistent() {
    grep -hqE '^[[:space:]]*umask[[:space:]]+0?027' \
        /home/alice/.bash_profile /home/alice/.bashrc /home/alice/.profile 2>/dev/null
}

errcount_ok() {
    local student expected
    [ -s /opt/reports/error-count.txt ] || return 1
    [ -s "${EXPECTED}/errcount.txt" ] || return 1
    student=$(tr -dc '0-9' < /opt/reports/error-count.txt)
    expected=$(tr -dc '0-9' < "${EXPECTED}/errcount.txt")
    [ -n "$student" ] && [ "$student" = "$expected" ]
}

pkg_installed() {   # dnf-based package presence test (no rpm)
    if command -v dnf >/dev/null 2>&1; then
        dnf list --installed "$1" >/dev/null 2>&1 && return 0
    elif command -v yum >/dev/null 2>&1; then
        yum list installed "$1" >/dev/null 2>&1 && return 0
    fi
    return 1
}

tree_installed()  { pkg_installed tree || command -v tree >/dev/null 2>&1; }
zsh_removed()     { ! pkg_installed zsh && ! command -v zsh >/dev/null 2>&1; }

hostname_file_ok() {
    [ -s /opt/reports/hostname.txt ] || return 1
    head -1 /opt/reports/hostname.txt | tr -d '[:space:]' | grep -qx 'exam-node1.example.com'
}

cron_line() { crontab -l -u alice 2>/dev/null | grep -vE '^[[:space:]]*#'; }

#------------------------------------------------------------------------------
echo "==============================================================="
echo "   LINUX PRACTICAL EXAM - AUTOMATED GRADING"
echo "   Candidate : ${CANDIDATE}"
echo "   Host      : $(hostname)   Date: $(date)"
echo "==============================================================="

#------------------------------------------------------------------------------
question "Q1  Users and groups"
check "Group 'sysadmins' exists with GID 5000" 2 \
      "[ \"\$(getent group sysadmins | cut -d: -f3)\" = 5000 ]"
check "Users alice and bob exist with /bin/bash" 2 \
      "[ \"\$(field_passwd alice 7)\" = /bin/bash ] && [ \"\$(field_passwd bob 7)\" = /bin/bash ]"
check "alice and bob are members of sysadmins" 1 \
      "user_in_group alice sysadmins && user_in_group bob sysadmins"
check "carol has UID 3005 and a nologin shell" 1 \
      "[ \"\$(id -u carol)\" = 3005 ] && field_passwd carol 7 | grep -qE '^/(usr/)?sbin/nologin$'"
check "carol comment field is 'Service Account'" 1 \
      "field_passwd carol 5 | grep -qx 'Service Account'"

#------------------------------------------------------------------------------
question "Q2  Password ageing and account locking"
check "alice password max age = 45 days" 2 \
      "[ \"\$(chage_value alice 'Maximum number of days')\" = 45 ]"
check "alice password min age = 3 days" 1 \
      "[ \"\$(chage_value alice 'Minimum number of days')\" = 3 ]"
check "alice password warning period = 7 days" 1 \
      "[ \"\$(chage_value alice 'Number of days of warning')\" = 7 ]"
check "Account dev01 is locked" 1 "acct_locked dev01"

#------------------------------------------------------------------------------
question "Q3  Superuser access via sudo"
check "Drop-in file /etc/sudoers.d/sysadmins exists" 1 "[ -f /etc/sudoers.d/sysadmins ]"
check "sudo configuration passes syntax check" 1 "visudo -c"
check "alice may run all commands with NOPASSWD" 2 "sudo_nopasswd alice"
check "bob may run all commands with NOPASSWD" 1 "sudo_nopasswd bob"

#------------------------------------------------------------------------------
question "Q4  Ownership and permissions"
check "/opt/projects/webapp exists and is a directory" 1 "[ -d /opt/projects/webapp ]"
check "webapp owned by alice:sysadmins" 2 \
      "[ \"\$(owner_of /opt/projects/webapp)\" = alice ] && [ \"\$(group_of /opt/projects/webapp)\" = sysadmins ]"
check "webapp permission is 770" 1 "[ \"\$(mode_of /opt/projects/webapp)\" = 770 ]"
check "notes.txt owned by bob:sysadmins with mode 640" 1 \
      "[ \"\$(owner_of /opt/projects/webapp/notes.txt)\" = bob ] && [ \"\$(group_of /opt/projects/webapp/notes.txt)\" = sysadmins ] && [ \"\$(mode_of /opt/projects/webapp/notes.txt)\" = 640 ]"

#------------------------------------------------------------------------------
question "Q5  Access Control Lists"
check "ACL grants user bob rwx on webapp" 3 \
      "getfacl -p /opt/projects/webapp 2>/dev/null | grep -qx 'user:bob:rwx'"
check "Default ACL grants user carol r-x" 3 \
      "getfacl -p /opt/projects/webapp 2>/dev/null | grep -qx 'default:user:carol:r-x'"

#------------------------------------------------------------------------------
question "Q6  umask for alice"
check "alice's effective umask is 0027" 2 "alice_umask"
check "umask setting is persistent in alice's login files" 2 "umask_persistent"

#------------------------------------------------------------------------------
question "Q7  Locating and copying large files"
check "/opt/reports/bigfiles directory exists" 1 "[ -d /opt/reports/bigfiles ]"
check "All files larger than 1 MiB were copied" 2 "bigfiles_present"
check "Original permissions preserved on copies" 1 "bigfiles_modes_ok"
check "Original timestamps preserved on copies" 1 "bigfiles_times_ok"

#------------------------------------------------------------------------------
question "Q8  Permission audit and cleanup"
check "world-writable.txt lists exactly the 0777 files, sorted" 3 "ww_list_ok"
check "All empty files under /exam-data/tmpdir removed" 1 "no_empty_files"
check "Non-empty files in tmpdir left intact" 1 \
      "[ -s ${DATA}/tmpdir/keep1.txt ] && [ -s ${DATA}/tmpdir/keep2.txt ]"

#------------------------------------------------------------------------------
question "Q9  Log analysis"
check "error-count.txt holds the correct count" 3 "errcount_ok"
check "ips.txt holds the unique, sorted IPv4 addresses" 3 \
      "same_file_content /opt/reports/ips.txt ${EXPECTED}/ips.txt"
check "lines10-20.txt holds lines 10-20 of numbers.txt" 3 \
      "same_file_content /opt/reports/lines10-20.txt ${EXPECTED}/lines.txt"

#------------------------------------------------------------------------------
question "Q10 Hard and soft links"
check "master.hard is a hard link (same inode) to master.cfg" 2 \
      "[ -f /opt/reports/master.hard ] && [ ! -L /opt/reports/master.hard ] && same_inode /opt/reports/master.hard ${DATA}/config/master.cfg"
check "master.soft is a symlink to master.cfg" 2 \
      "[ -L /opt/reports/master.soft ] && [ \"\$(readlink -f /opt/reports/master.soft)\" = ${DATA}/config/master.cfg ]"

#------------------------------------------------------------------------------
question "Q11 Archiving"
check "/opt/backups/exam-data.tar.gz exists and is gzip data" 1 \
      "[ -f /opt/backups/exam-data.tar.gz ] && file /opt/backups/exam-data.tar.gz | grep -qi gzip"
check "Archive contains config/master.cfg" 2 \
      "tar -tzf /opt/backups/exam-data.tar.gz | grep -q 'config/master.cfg'"
check "Archive contains app.conf and db.conf as well" 1 \
      "tar -tzf /opt/backups/exam-data.tar.gz | grep -q 'config/app.conf' && tar -tzf /opt/backups/exam-data.tar.gz | grep -q 'config/db.conf'"

#------------------------------------------------------------------------------
question "Q12 Rogue workload stopped"
check "exam-rogue.service is not active" 2 "! systemctl is-active --quiet exam-rogue.service"
check "exam-rogue.service will not start at boot" 2 "! systemctl is-enabled --quiet exam-rogue.service"
check "No exam-rogue.sh process is running" 1 "rogue_stopped"

#------------------------------------------------------------------------------
question "Q13 Custom systemd service"
check "/usr/local/bin/examlog.sh exists and is executable" 2 "[ -x /usr/local/bin/examlog.sh ]"
check "Unit file examlog.service exists" 1 \
      "systemctl cat examlog.service >/dev/null 2>&1"
check "examlog.service is active" 2 "systemctl is-active --quiet examlog.service"
check "examlog.service is enabled at boot" 2 "systemctl is-enabled --quiet examlog.service"
echo "         (waiting 25s to confirm /var/log/examlog.log is growing...)"
check "/var/log/examlog.log is being written to" 1 "log_is_growing /var/log/examlog.log 25"

#------------------------------------------------------------------------------
question "Q14 Package management"
check "Package 'tree' is installed" 2 "tree_installed"
check "Package 'zsh' has been removed" 2 "zsh_removed"

#------------------------------------------------------------------------------
question "Q15 Partition, file system and persistent mount"
check "/mnt/examdata is mounted" 2 "mountpoint -q /mnt/examdata"
check "File system on /mnt/examdata is ext4" 2 "[ \"\$(mounted_fstype /mnt/examdata)\" = ext4 ]"
check "File system label is EXAMDATA" 1 \
      "blkid -s LABEL -o value \"\$(mounted_source /mnt/examdata)\" 2>/dev/null | grep -qx EXAMDATA"
check "Size is approximately 500 MiB" 1 "between \"\$(mount_size_mb /mnt/examdata)\" 400 560"
check "Persistent entry present in /etc/fstab" 2 "fstab_has /mnt/examdata"

#------------------------------------------------------------------------------
question "Q16 LVM create and extend"
check "Volume group 'vgexam' exists" 2 "vgs --noheadings -o vg_name 2>/dev/null | grep -qw vgexam"
check "Logical volume 'lvdata' exists in vgexam" 1 "lvs --noheadings -o lv_name vgexam 2>/dev/null | grep -qw lvdata"
check "lvdata has been extended to about 1 GiB" 2 "between \"\$(lv_size_mb vgexam lvdata)\" 970 1100"
check "/mnt/lvdata is mounted with xfs" 2 \
      "mountpoint -q /mnt/lvdata && [ \"\$(mounted_fstype /mnt/lvdata)\" = xfs ]"
check "xfs file system was grown to match the LV" 2 "between \"\$(mount_size_mb /mnt/lvdata)\" 900 1100"
check "Persistent entry present in /etc/fstab" 1 "fstab_has /mnt/lvdata"

#------------------------------------------------------------------------------
question "Q17 Scheduled job for alice"
check "alice has a cron job running every 5 minutes" 2 \
      "cron_line | grep -qE '^\\*/5[[:space:]]+\\*[[:space:]]+\\*[[:space:]]+\\*[[:space:]]+\\*'"
check "The job appends to /home/alice/cron-report.txt" 1 \
      "cron_line | grep -q '/home/alice/cron-report.txt'"

#------------------------------------------------------------------------------
question "Q18 Hostname"
check "Static hostname is exam-node1.example.com" 2 \
      "hostnamectl --static 2>/dev/null | grep -qx 'exam-node1.example.com' || grep -qx 'exam-node1.example.com' /etc/hostname"
check "/opt/reports/hostname.txt contains the hostname" 1 "hostname_file_ok"

flush_q

#------------------------------------------------------------------------------
# Final report
#------------------------------------------------------------------------------
PERCENT=0
[ "$TOTAL" -gt 0 ] && PERCENT=$(( EARNED * 100 / TOTAL ))

echo
echo "==============================================================="
echo "                    RESULT SUMMARY"
echo "==============================================================="
for line in "${SUMMARY[@]}"; do echo "  $line"; done
echo "---------------------------------------------------------------"
printf "  %-48s %3d / %3d\n" "TOTAL" "$EARNED" "$TOTAL"
printf "  %-48s %3d%%\n" "PERCENTAGE" "$PERCENT"
echo "---------------------------------------------------------------"
if [ "$PERCENT" -ge "$PASS_PERCENT" ]; then
    echo -e "  RESULT: ${GRN}PASS${NC}  (pass mark ${PASS_PERCENT}%)"
else
    echo -e "  RESULT: ${RED}FAIL${NC}  (pass mark ${PASS_PERCENT}%)"
fi
echo "==============================================================="

{
    echo "Linux Practical Exam - Result"
    echo "Candidate : ${CANDIDATE}"
    echo "Host      : $(hostname)"
    echo "Date      : $(date)"
    echo "-----------------------------------------------------------"
    for line in "${SUMMARY[@]}"; do echo "  $line"; done
    echo "-----------------------------------------------------------"
    printf "  %-48s %3d / %3d (%d%%)\n" "TOTAL" "$EARNED" "$TOTAL" "$PERCENT"
    if [ "$PERCENT" -ge "$PASS_PERCENT" ]; then echo "  RESULT: PASS"; else echo "  RESULT: FAIL"; fi
} > "$REPORT"

echo "  Transcript saved to: ${REPORT}"
echo
