# 🚀 Devkit by Usual Expat


## 🔹 What

This repository provides a **pragmatic, versatile, and visually appealing** configuration setup for developers. It includes:  

- **Git** – Streamlined config with useful aliases and signing setup  
- **PowerShell** – Custom profiles, productivity scripts, and automation  
- **Windows Terminal** – Beautiful themes, shortcuts, and profiles  
- **.NET Project Templates** – Ready-to-use templates designed for **Azure DevOps** and **Terraform**  
- **DevOps & Terraform Integration** – Optimized for cloud-native workflows  

Everything is designed to be **easy to set up, powerful, and visually refined**.

![assets/windows-terminal-screenshot.png](assets/windows-terminal-screenshot.png)

**Note**: this is very much work in progress, and the configuration provided is rather custom to my needs, so might need some edits to make sure it suits your needs. Sharing early as the terminal configuration was requested by a friend. The plan is to make the installation and management of configs easy and user friendly, making sure that setting up a new box for development is automated and personalised to the user.

---

## 🔹 How  

### 🚀 **Installation & Setup**

1. **Clone this repo**  

   ```powershell
   git clone https://github.com/mgpeter/usualexpat-devkit.git
   cd usualexpat-devkit
   ```

2. **Install required powershell modules and oh-my-posh**

   Run as admin:

    ```powershell
    . "./configuration/powershell/install.ps1"
    ```

3. **Customize & Enjoy**  

   - Adjust settings in `configuration/` if needed.
   - Edit your powershell `$PROFILE` to include the following, adjust the path to where the repo is cloned:

    ```powershell
    # Path to your separate script file
    $scriptPath = "D:\repos\usualexpat-devkit\configuration\powershell\Microsoft.PowerShell_profile.ps1"

    . $scriptPath
    ```

---

## 🔹 Who  

This kit is for **developers, DevOps engineers, and power users** who want:  

✅ A **polished** and **efficient** development environment  
✅ Quick but **flexible** setup for Git, PowerShell, and Windows Terminal  
✅ Ready-to-go **.NET templates** for **Azure DevOps** and **Terraform** projects  
✅ A **beautiful** CLI experience without hassle  

Whether you’re a **beginner looking for a strong starting point** or a **seasoned developer** looking to streamline your workflow, this kit will help you get up and running fast! 🚀  

## 🔹 Status

- ✔️ Initial git and powershell configs **[DONE]**

  - Powershell configuration including useful modules and **oh-my-posh**
  - Multi-account setup for git

- ⚒️ Automated install scripts for powershell and git configuration **[IN PROGRESS]**

  - ⚒️ automated installation of powershell modules **[IN PROGRESS]**
  - ❌ interactive configuration of powershell profile **[IN PROGRESS]**
  - ❌ automated installation of git configuration **[TO DO]**
  - ❌ interactive configuration of multi-account setup for git **[TO DO]**

- ❌ Powershell and git documentation **[TO DO]**

- ❌ Automated install scripts for Azure CLI multi-tenant setup **[TO DO]**

- ❌ Generic Terraform templates and shared code **[TO DO]**

- ❌ Automated dotnet and Azure Dev Ops project setup **[TO DO]**