# Linux System Administration — Practical Examination

**Platform:** CentOS Stream 10 (VirtualBox VM)
**Duration:** 2 hours 30 minutes
**Total marks:** 100
**Passing score:** 80

---

## Pre-exam setup (manual prerequisites — complete before the candidate starts)

These steps must be done by the invigilator on the exam VM **before** running `exam_setup.sh`.

### 1. Attach two spare virtual disks (3 GB and 5 GB)

The storage questions (15 and 16) require two blank virtual disks attached to the VM. Attach them in VirtualBox as follows:

1. Shut down the VM (VirtualBox can also hot-add disks to a running VM if the controller supports it, but doing this with the VM powered off is safest).
2. Open **VirtualBox Manager** → select the exam VM → **Settings** → **Storage**.
3. Under the **SATA** (or **SCSI**) controller, click the **Add Hard Disk** icon (the small disk-with-plus icon).
4. Click **Create** to make a new virtual disk:
   - Choose **VDI** (or your preferred format), **Dynamically allocated**.
   - Set the size to **3 GB**. Give it a recognizable name, e.g. `exam-disk1`.
   - Click **Create** to attach it.
5. Repeat steps 3–4 to add a **second** disk of **5 GB**, e.g. `exam-disk2`.
6. Click **OK** to close Settings, then start the VM.
7. Inside the VM, confirm both disks are visible with `lsblk` — they typically appear as `/dev/sdb` (3 GB) and `/dev/sdc` (5 GB). `exam_setup.sh` auto-detects them.

### 2. Take a snapshot before running the exam setup

Take a clean snapshot so the VM can be restored to a pristine state for the next candidate.

1. In **VirtualBox Manager**, select the exam VM.
2. Go to **Machine** → **Take Snapshot** (or click the **Snapshots** icon in the toolbar, then **Take**).
3. Give it a clear name, e.g. `pre-exam-clean` or `before-exam-setup`, and click **OK**.
4. Confirm the snapshot appears under the **Snapshots** pane before continuing.

If anything goes wrong during setup or grading, restore this snapshot (**Snapshots** → right-click the snapshot → **Restore**) and start again.

### 3. Set up the exam environment

Once the disks are attached and the snapshot is taken, start the VM and run, as root:

```bash
cd /path/to/exam-1
./exam_setup.sh
```

- The script installs required packages, prepares `/exam-data`, creates the pre-existing accounts (`dev01`) and the rogue service, detects the two spare disks, and records everything in `/etc/exam/exam.env`.
- To reuse the same VM for another candidate, reset first: `./exam_setup.sh --reset --yes`.
- When setup finishes, hand the candidate `exam_questions.md` and start the clock.

### 4. Check the result after the exam

When the candidate has finished (or time is up), run, as root:

```bash
./exam_check.sh <candidate-name>
```

- The script inspects the system, prints a pass/fail breakdown per question, and waits ~25 seconds to confirm Question 13's log file is growing.
- A transcript is saved to `/root/exam-result-<candidate-name>-<date>.txt`.
- A reboot before grading is a fair sanity check of the "must survive a reboot" rule.

---

## Instructions — read before you start

1. This is a **100% practical exam**. Nothing has to be written on paper: your work is the state you leave the system in. An automated script inspects the server afterwards and awards marks.
2. Perform all tasks on the exam server as `root` (or with `sudo`).
3. **Everything must survive a reboot.** Mounts, services, hostname and cron jobs will be checked on a running system; if a change only exists in memory, it earns no marks.
4. Two spare virtual disks have been attached to this VM for the storage tasks. Their device names (typically `/dev/sdb` and `/dev/sdc`) are recorded in `/etc/exam/exam.env`:
   ```
   source /etc/exam/exam.env
   echo $EXAM_DISK1 $EXAM_DISK2
   lsblk
   ```
   Use `$EXAM_DISK1` only for Question 15 and `$EXAM_DISK2` only for Question 16. Do **not** touch the disk that holds the running system.
5. Do **not** modify or delete anything under `/etc/exam/` and do not edit the source data under `/exam-data/` unless a question tells you to. Tampering is detected and scores zero for the affected question.
6. This system is CentOS Stream 10: use `dnf` for package management (`yum` still works as a compatibility link).
7. `man`, `--help` and the documentation in `/usr/share/doc` are allowed. The internet is not.
8. Exact names, paths, permissions and spellings matter. Read each question twice.

---

## Section A — Users, Groups and Privileges (22 marks)

### Question 1 — User and group management (7 marks)

1. Create a group named `sysadmins` with GID **5000**.
2. Create two users, `alice` and `bob`, each with:
   - a normal interactive shell (`/bin/bash`),
   - a home directory under `/home`,
   - `sysadmins` as a **secondary** group.
3. Create a third user `carol` with:
   - UID **3005**,
   - login shell `/sbin/nologin` (no interactive access),
   - the comment field set exactly to `Service Account`.

### Question 2 — Password ageing and account locking (5 marks)

1. Configure the account `alice` so that her password:
   - must be changed at least every **45** days,
   - cannot be changed again for **3** days after a change,
   - warns her **7** days before it expires.
2. The pre-existing account `dev01` has left the company. **Lock** the account so the password can no longer be used. Do not delete it.

### Question 3 — Superuser access (5 marks)

Grant every member of the `sysadmins` group the ability to run **all commands** with `sudo`, on **all hosts**, **without being prompted for a password**.

- The configuration must be added as a separate drop-in file named `/etc/sudoers.d/sysadmins` (do not edit `/etc/sudoers` directly).
- The resulting configuration must pass a syntax check.

### Question 4 — Ownership and permissions (5 marks)

1. Create the directory `/opt/projects/webapp`.
2. It must be owned by user `alice` and group `sysadmins`, with octal permission **770**.
3. Inside it, create a file named `notes.txt` owned by user `bob` and group `sysadmins`, with octal permission **640**.

---

## Section B — ACLs and Default Permissions (10 marks)

### Question 5 — Access Control Lists (6 marks)

On the directory `/opt/projects/webapp`, without changing its base ownership or its 770 mode:

1. Give the user `bob` explicit **read, write and execute** access through an ACL entry.
2. Configure a **default ACL** so that every new file or directory created inside `/opt/projects/webapp` automatically grants the user `carol` **read and execute** access.

### Question 6 — umask (4 marks)

Configure user `alice` so that **her** default file-creation mask is **0027** every time she logs in. The change must apply to `alice` only — it must not alter the system-wide default for other users.

---

## Section C — Finding, Copying and Processing Files (19 marks)

### Question 7 — Locating and copying large files (5 marks)

1. Create the directory `/opt/reports/bigfiles`.
2. Find every **regular file** under `/exam-data` that is **larger than 1 MiB** and copy it into `/opt/reports/bigfiles`.
3. The copies must **preserve the original permissions and timestamps**.

### Question 8 — Permission audit and cleanup (5 marks)

1. Find every regular file under `/exam-data` whose permissions are exactly **0777** and write their **full paths**, one per line in sorted order, into `/opt/reports/world-writable.txt`.
2. Delete every **empty** regular file under `/exam-data/tmpdir`. Files that contain data must be left untouched.

### Question 9 — Log analysis (9 marks)

All output files go in `/opt/reports`. Work from `/exam-data/logs/app.log` and `/exam-data/data/numbers.txt`.

1. **(3 marks)** Write the **number of lines** in `app.log` that contain the string `error`, ignoring case, into `/opt/reports/error-count.txt`. The file must contain the number only.
2. **(3 marks)** Extract every **IPv4 address** that appears in `app.log`, remove duplicates, sort them, and write them one per line into `/opt/reports/ips.txt`.
3. **(3 marks)** Write **lines 10 to 20 inclusive** of `numbers.txt` into `/opt/reports/lines10-20.txt`.

---

## Section D — Links and Archiving (8 marks)

### Question 10 — Hard and soft links (4 marks)

1. Create a **hard link** at `/opt/reports/master.hard` pointing to `/exam-data/config/master.cfg`.
2. Create a **symbolic link** at `/opt/reports/master.soft` pointing to `/exam-data/config/master.cfg`.

### Question 11 — Archiving (4 marks)

Create a **gzip-compressed tar archive** at `/opt/backups/exam-data.tar.gz` containing the whole `/exam-data/config` directory and all files inside it.

---

## Section E — Processes and Services (13 marks)

### Question 12 — Terminate a rogue workload (5 marks)

A runaway workload called `exam-rogue.service` is consuming resources on this server.

1. Stop it so that no `exam-rogue.sh` process is running.
2. Make sure it will **not** start again after a reboot.

### Question 13 — Create your own service (8 marks)

Create a systemd service called `examlog.service` that behaves as follows:

1. It runs the script `/usr/local/bin/examlog.sh`, which must be executable and must, **every 10 seconds and forever**, append a line containing the current date and time to `/var/log/examlog.log`.
2. The service must be **started now** and must be **enabled to start automatically at boot** under the `multi-user.target`.
3. `/var/log/examlog.log` must be actively growing when the exam is graded.

---

## Section F — Software Management (4 marks)

### Question 14 — Packages (4 marks)

1. Install the package **`tree`** from the configured repositories.
2. The package **`zsh`** is installed on this server but is no longer approved. **Uninstall** it.

Use `dnf` for both tasks.

---

## Section G — Storage (18 marks)

### Question 15 — Partition, file system and persistent mount (8 marks)

On **`$EXAM_DISK1`** only:

1. Create a single partition of approximately **500 MiB**.
2. Format it with the **ext4** file system and give it the label **`EXAMDATA`**.
3. Mount it **permanently** on `/mnt/examdata`, so that it is mounted automatically at boot.

### Question 16 — LVM (10 marks)

On **`$EXAM_DISK2`** only:

1. Prepare the disk for LVM and create a volume group named **`vgexam`**.
2. Create a logical volume named **`lvdata`** of **512 MiB**, format it with **xfs** and mount it permanently on `/mnt/lvdata`.
3. The application then needs more space: **extend `lvdata` to 1 GiB and grow its file system** so that the extra space is usable on `/mnt/lvdata`, **without unmounting it and without losing data**.

---

## Section H — Scheduling and Networking (6 marks)

### Question 17 — Scheduled job (3 marks)

Schedule a job for the user `alice` (not root) that runs **every 5 minutes** and appends the current date and time to `/home/alice/cron-report.txt`.

### Question 18 — Hostname (3 marks)

1. Set the system's static hostname permanently to **`exam-node1.example.com`**.
2. Write that hostname — and nothing else — into `/opt/reports/hostname.txt`.

---

**Good luck.**
