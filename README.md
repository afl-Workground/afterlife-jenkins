# AfterlifeOS Builder

[![GitHub Actions](https://github.com/AfterlifeOS/AfterlifeOS-Builder/actions/workflows/afterlife_build.yml/badge.svg)](https://github.com/AfterlifeOS/AfterlifeOS-Builder/actions/workflows/afterlife_build.yml)

A robust and automated build system for AfterlifeOS, designed for efficiency, scalability, and seamless integration with CI/CD platforms like GitHub Actions and Jenkins. This builder provides intelligent management of source code synchronization, compilation, and artifact distribution, all with real-time feedback.

---

## ✨ Features

*   **Dual CI/CD Integration:** Supports both GitHub Actions (self-hosted runners) and Jenkins pipelines.
*   **Intelligent Quota Management:** Prevents server overload with queue depth checks and a daily build quota system for regular users, while providing unlimited access for administrators (GitHub Actions only).
*   **Optimized Build Process:**
    *   **Smart Dirty Builds:** Automatically detects if a full source wipe is needed or if a faster "dirty" build is feasible based on device changes.
    *   **Persistent Directories:** Utilizes persistent `ROOTDIR` and `CCACHE_DIR` outside the temporary workspace to maximize build speed and efficiency across runs.
*   **Real-time Telegram Notifications:** Provides instant updates on build status (start, detailed progress, success, failure, cancellation) directly to Telegram.
*   **Large Artifact Handling:** Automatically uploads large build artifacts (>2GB, exceeding GitHub's artifact limits) to external services like Gofile.io, providing a direct download link.
*   **Flexible Local Manifest Support:** Easily integrate custom device trees or overlay repositories via a URL to your local manifest XML.

## 🚀 Getting Started

This guide covers how to trigger and monitor builds using both supported CI/CD platforms.

### Prerequisites

*   **GitHub Actions:**
    *   A GitHub account.
    *   Access to this repository (as a collaborator with `write` permission to run workflows).
    *   A self-hosted GitHub Actions runner configured and online (as specified in `.github/workflows/afterlife_build.yml`).
    *   Configured Telegram bot token and chat ID as repository secrets (`TELEGRAM_TOKEN`, `TELEGRAM_CHAT_ID`).
*   **Jenkins:**
    *   A running Jenkins instance.
    *   Configured Telegram credentials (e.g., `telegram-bot-token`, `telegram-chat-id`) in Jenkins Global Credentials.
    *   (Optional) A self-hosted Jenkins agent or configured build environment capable of Android compilation.

### Using the GitHub Actions Workflow

1.  **Navigate to Actions:** In your repository, go to the `Actions` tab.
2.  **Select Workflow:** From the left sidebar, select the `AfterlifeOS Builder` workflow.
3.  **Run Workflow:** Click on the `Run workflow` dropdown button on the right side.
4.  **Provide Inputs:** Fill in the required build parameters:
    *   `DEVICE`: The codename of the device you want to build (e.g., `raven`, `surya`). **(Required)**
    *   `BUILD_TYPE`: The type of build (`userdebug`, `user`, `eng`). **(Required)**
    *   `BUILD_VARIANT`: The build variant (`test`, `release`). **(Required)**
    *   `LOCAL_MANIFEST_URL`: A URL pointing to your raw XML local manifest (e.g., from a GitHub Gist or your own repository). **(Required)**
    *   `CLEAN_BUILD`: Set to `true` for a full clean build. (Admins only)
    *   `DIRTY_BUILD`: Set to `true` to force a dirty build, skipping manifest wipe.
5.  **Trigger Build:** Click the green `Run workflow` button.
6.  **Monitor Progress:**
    *   You will receive real-time updates and the final build result directly in your configured Telegram chat.
    *   You can also view the detailed build log on the GitHub Actions page.

### Using the Jenkins Pipeline

1.  **Create Pipeline Job:** In your Jenkins instance, create a new "Pipeline" job.
2.  **Configure Pipeline Script:** Select "Pipeline script from SCM" or directly paste the content of `jenkins/Jenkinsfile` into the script area.
3.  **SCM Configuration (if from SCM):** Configure your SCM (e.g., Git) to point to this repository.
4.  **Credential Configuration:** Ensure your Telegram bot token and chat ID are configured as Jenkins credentials and correctly referenced in the `Jenkinsfile` (e.g., `credentials('telegram-bot-token')`).
5.  **Build with Parameters:** Configure the job to be parameterized, mirroring the inputs available in the GitHub Actions workflow (`DEVICE`, `BUILD_TYPE`, `LOCAL_MANIFEST_URL`, `TELEGRAM_TOPIC_ID`, `CLEAN_BUILD`, `DIRTY_BUILD`).
6.  **Run Build:** Trigger the build from the Jenkins UI, providing the necessary parameters.
7.  **Monitor Progress:** Monitor build progress and results via Telegram and the Jenkins console output.

## 🛠️ Configuration

Key build parameters and environment settings are primarily defined in `builder/config.sh`. It is crucial to understand these for optimal builder performance.

*   `ROM_NAME`: The name of your custom ROM (e.g., `AfterlifeOS`).
*   `MANIFEST_URL`: The URL to your base Android manifest repository (e.g., `https://github.com/AfterlifeOS/afterlife_manifest`).
*   `ROM_VERSION`: The branch name of the manifest you wish to sync (e.g., `16`).
*   `ROOTDIR`: The absolute path to the persistent directory where the Android source code will be synced. **Defaults to `~/android/source`.** This is critical for dirty builds and avoiding repeated full syncs.
*   `CCACHE_DIR`: The absolute path to the persistent `ccache` directory. **Defaults to `~/android/ccache`.** Essential for fast incremental builds.

## ⚙️ How It Works (Technical Overview)

The builder orchestrates several scripts and tools:

*   **`.github/workflows/afterlife_build.yml`**: The main GitHub Actions workflow definition, handling triggers, environment setup, and orchestrating the build stages.
*   **`jenkins/Jenkinsfile`**: The Groovy script defining the Jenkins declarative pipeline, mirroring the GitHub Actions logic.
*   **`builder/config.sh`**: Centralized configuration for ROM details, manifest URLs, and persistent directory paths.
*   **`builder/sync.sh`**: Manages the `repo init` and `repo sync` process, including smart dirty build logic, tracking local manifests, and cleaning up previous build artifacts.
*   **`builder/build.sh`**: The core build script. It sets up the build environment, executes the main `goafterlife` command, provides real-time progress monitoring via Telegram, and handles build status (success, failure, cancellation).
*   **`builder/smart_upload.sh`**: Executes post-build artifact handling, specifically for large files (>2GB) which are uploaded to Gofile.io to bypass GitHub Artifact size limitations.
*   **`builder/tg_utils.sh`**: A utility script providing modular functions for sending, editing, and uploading documents to Telegram, used throughout the build process for notifications.

## 🤝 Contributing

Contributions are welcome! If you find a bug or have an enhancement idea, please feel free to:
1.  Fork the repository.
2.  Create a new branch (`git checkout -b feature/your-feature`).
3.  Make your changes and ensure your code adheres to existing style.
4.  Submit a pull request.

## 📜 License

This project is licensed under the MIT License - see the `LICENSE.md` file for details.

## 📞 Support / Contact

For any questions or support, please open an issue in this repository.
