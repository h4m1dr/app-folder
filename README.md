# App-Folder

A lightweight, modular collection of interactive command-line application managers organized by programming runtime (`node-js`, `go`, etc.).

---

## Directory Structure

```text
app-folder/
├── README.md
└── node-js/
    ├── NodejsEasy
    └── 9router.sh

```

---

## NodejsEasy

`NodejsEasy` is the core management interface for Node.js-based services. It manages the underlying Node.js runtime, performs garbage collection on build caches, and dynamically auto-loads any application script (`*.sh`) placed inside the `node-js/` directory.

### Features

* **Zero Configuration Discovery:** Drop any application script (e.g. `9router.sh`) directly into `node-js/`, and it immediately shows up in the main menu.
* **Complete Lifecycle Management:** Install, update, start, stop, restart, and delete services with systemd persistence.
* **Smart Cache Wiper:** Cleans obsolete NPM packages, build artifacts, APT deb archives, and prunes systemd journals.

---

## Installation & Setup

### Option 1: Run directly from GitHub

Run directly in memory without cloning the full repository:

```bash
bash <(curl -fsSL [https://raw.githubusercontent.com/h4m1dr/app-folder/main/node-js/NodejsEasy](https://raw.githubusercontent.com/h4m1dr/app-folder/main/node-js/NodejsEasy))

```

---

### Option 2: Clone & Global System Command (Recommended)

1. Clone the repository into `/opt/app-folder`:
```bash
git clone [https://github.com/h4m1dr/app-folder.git](https://github.com/h4m1dr/app-folder.git) /opt/app-folder

```


2. Make the scripts executable:
```bash
chmod +x /opt/app-folder/node-js/NodejsEasy
chmod +x /opt/app-folder/node-js/*.sh

```


3. Create a global command symlink:
```bash
ln -sf /opt/app-folder/node-js/NodejsEasy /usr/local/bin/nodejs-easy

```


4. Launch the manager from any terminal window:
```bash
nodejs-easy

```



---

## Adding New Applications

To add another Node.js application to this manager:

1. Create a script named `<app-name>.sh` directly inside `node-js/`.
2. Implement the standard lifecycle functions (`app_install`, `app_update`, `app_start`, `app_stop`, `app_restart`, `app_delete`, and `app_menu`).
3. Make it executable (`chmod +x <app-name>.sh`).

The application will be registered as a selectable menu entry automatically on the next run.


