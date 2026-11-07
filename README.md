# App-Folder

A lightweight, modular collection of interactive command-line application managers organized by programming runtime (`Node-js`, `Golang`, etc.).

---

## Directory Structure

```text
app-folder/
├── README.md
├── Node-js/
│   ├── NodejsEasy
│   └── 9router.sh
└── Golang/
    ├── GolangEasy
    ├── authelia.sh
    └── cliproxyapi.sh

```

---

## NodejsEasy

`NodejsEasy` is the core management interface for Node.js-based services. It manages the underlying Node.js runtime, performs garbage collection on build caches, and dynamically auto-loads any application script (`*.sh`) placed inside the `Node-js/` directory.

### Features

* **Zero Configuration Discovery:** Drop any application script (e.g. `9router.sh`) directly into `Node-js/`, and it immediately shows up in the main menu.
* **Complete Lifecycle Management:** Install, update, start, stop, restart, and delete services with systemd persistence.
* **Smart Cache Wiper:** Cleans obsolete NPM packages, build artifacts, APT deb archives, and prunes systemd journals.

### Installation & Setup

#### Option 1: Run directly from GitHub

Run directly in memory without cloning the full repository:

```bash
bash <(curl -fsSL [https://raw.githubusercontent.com/h4m1dr/app-folder/main/Node-js/NodejsEasy](https://raw.githubusercontent.com/h4m1dr/app-folder/main/Node-js/NodejsEasy)) </dev/tty

```

#### Option 2: Clone & Global System Command (Recommended)

1. Clone the repository into `/opt/app-folder`:

```bash
mkdir -p /opt/app-folder
git clone [https://github.com/h4m1dr/app-folder.git](https://github.com/h4m1dr/app-folder.git) /opt/app-folder

```

2. Make the scripts executable:

```bash
chmod +x /opt/app-folder/Node-js/NodejsEasy
chmod +x /opt/app-folder/Node-js/*.sh

```

3. Create a global command symlink:

```bash
ln -sf /opt/app-folder/Node-js/NodejsEasy /usr/local/bin/nodejs-easy

```

4. Launch the manager from any terminal window:

```bash
nodejs-easy

```

---

## GolangEasy

`GolangEasy` is the unified management interface for native, high-performance Go-based microservices and authentication gateways. It provides Go toolchain management, garbage collection for build/module caches, and dynamic discovery of Go application modules (`*.sh`) within the `Golang/` directory.

### Features

* **Native Binary Performance:** Zero-overhead execution using native ELF binaries without runtime bloat.
* **Dynamic Application Discovery:** Automatically detects and indexes standalone scripts (e.g. `authelia.sh`, `cliproxyapi.sh`) into the menu.
* **Integrated Service Lifecycle:** Installs official GitHub binary releases, configures systemd units, handles 2FA onboarding, and monitors logs.
* **Deep Cache Cleanup:** Cleans Go compiler cache, test cache, module cache (`$GOPATH/pkg`), and transient system build remnants.

### Installation & Setup

#### Option 1: Run directly from GitHub

Execute directly in memory:

```bash
bash <(curl -fsSL [https://raw.githubusercontent.com/h4m1dr/app-folder/main/Golang/GolangEasy](https://raw.githubusercontent.com/h4m1dr/app-folder/main/Golang/GolangEasy)) </dev/tty

```

#### Option 2: Clone & Global System Command (Recommended)

1. Clone the repository into `/opt/app-folder` (if not already cloned):

```bash
mkdir -p /opt/app-folder
git clone [https://github.com/h4m1dr/app-folder.git](https://github.com/h4m1dr/app-folder.git) /opt/app-folder

```

2. Make the scripts executable:

```bash
chmod +x /opt/app-folder/Golang/GolangEasy
chmod +x /opt/app-folder/Golang/*.sh

```

3. Create a global command symlink:

```bash
ln -sf /opt/app-folder/Golang/GolangEasy /usr/local/bin/golang-easy

```

4. Launch the manager from any terminal window:

```bash
golang-easy

```

---

## Adding New Applications

To add another service to either runtime manager:

1. Create a script named `<app-name>.sh` directly inside the target directory (`Node-js/` or `Golang/`).
2. Implement the standard lifecycle functions:
* `app_is_installed`
* `app_init_metadata`
* `app_install`
* `app_update`
* `app_start`
* `app_stop`
* `app_restart`
* `app_status`
* `app_delete`
* `app_menu`


3. Grant execution permissions (`chmod +x <app-name>.sh`).

The application will be recognized and rendered as a selectable menu entry automatically on the next run.
