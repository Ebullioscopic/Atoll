
<div align="center">
   <img src="https://github.com/Ebullioscopic/DynamicIsland/blob/main/DynamicIslandSamples/logo.png" alt="DynamicIsland Logo" width="120"/>
</div>

# DynamicIsland

<p align="center">
   <b>Transform your MacBook's notch into a powerful, interactive control center.</b><br>
   <i>Advanced system monitoring, music controls, timers, widgets, and more — all with beautiful animations and intelligent layouts.</i>
</p>

<p align="center">
   <a href="https://github.com/Ebullioscopic/DynamicIsland/stargazers"><img src="https://img.shields.io/github/stars/Ebullioscopic/DynamicIsland?style=social"/></a>
   <a href="https://github.com/Ebullioscopic/DynamicIsland/network/members"><img src="https://img.shields.io/github/forks/Ebullioscopic/DynamicIsland?style=social"/></a>
   <a href="https://github.com/Ebullioscopic/DynamicIsland/issues"><img src="https://img.shields.io/github/issues/Ebullioscopic/DynamicIsland"/></a>
   <a href="https://github.com/Ebullioscopic/DynamicIsland/pulls"><img src="https://img.shields.io/github/issues-pr/Ebullioscopic/DynamicIsland"/></a>
</p>

---

## 📑 Table of Contents

- [🎬 Demo](#-demo)
- [✨ Features](#-features)
- [🚀 Getting Started](#-getting-started)
- [📖 Usage](#-usage)
- [⚙️ Configuration](#️-configuration)
- [🚧 Roadmap](#-roadmap)
- [🔧 Troubleshooting](#-troubleshooting)
- [🤝 Contributing](#-contributing)
- [📜 License](#-license)
- [🏆 Acknowledgments](#-acknowledgments)
- [👥 Contributors](#-contributors)

---

## 🎬 Demo

<div align="center">
   <img src="https://github.com/Ebullioscopic/DynamicIsland/blob/main/DynamicIslandSamples/dynamicislandscreenrecord.gif" alt="DynamicIsland Demo" width="700"/>
</div>

---

## ✨ Features

<div align="center">
   <img src="https://github.com/Ebullioscopic/DynamicIsland/blob/main/DynamicIslandSamples/statsmonitor.png" alt="Stats Monitor" width="350"/>
   <br>
   <img src="https://github.com/Ebullioscopic/DynamicIsland/blob/main/DynamicIslandSamples/media.png" alt="Media Controls" width="350"/>
</div>

### 🎵 Music & Media Controls
- **Live Music Activity**: Real-time album art, track info, and playback controls
- **Audio Visualizer**: Dynamic spectrum visualization with color adaptation
- **Multi-Platform Support**: Apple Music, Spotify, YouTube Music, and more
- **Smooth Transitions**: Elegant animations between tracks and states

### 📊 Advanced System Monitoring
- **CPU, Memory, GPU, Network, Disk**: Real-time stats with live graphs
- **Dual-Quadrant Graphs**: Network and disk stats show upload/download or read/write
- **Intelligent Layout**: Vertical expansion, 1-5 graph layouts, perfect centering
- **Customizable Visibility**: Toggle individual graphs on/off
- **Smooth Animations**: Debounced updates for fluid transitions

### 🎨 ColorPicker (NEW!)
<div align="center">
   <img src="https://github.com/Ebullioscopic/DynamicIsland/blob/main/DynamicIslandSamples/colorpickerpanel.png" alt="ColorPicker Panel" width="350"/>
   <br>
   <img src="https://github.com/Ebullioscopic/DynamicIsland/blob/main/DynamicIslandSamples/colorpickerpopover.png" alt="ColorPicker Popover" width="350"/>
</div>

- **Screen Color Picking**: Raycast-inspired panel, real-time magnification
- **Multiple Formats**: HEX, RGB, HSL, SwiftUI, UIColor, and more
- **History & Quick Copy**: Recent colors, hover info, click to copy
- **Global Shortcut**: Cmd+Shift+P (customizable)
- **Settings Integration**: Enable/disable, customize controls

### ⏱️ Timer & Productivity
- **Multiple Timers**: Create/manage named timers
- **Live Activities**: Background timer monitoring, notifications
- **Custom Colors**: Personalize timer appearance
- **Quick Access**: Direct timer controls from the notch

### 🔋 Battery & System Status
- **Intelligent Battery Alerts**: Smart notifications for charging states
- **Power Management**: Low battery warnings, charging status
- **System Integration**: Native macOS battery monitoring

### 🖥️ Modern UI & Animations
- **Smooth Transitions**: Professionally animated state changes
- **Hover Effects**: Interactive feedback, haptic support
- **Gesture Controls**: Swipe to open/close, tap interactions
- **Adaptive Sizing**: Dynamic height expansion for complex content
- **Perfect Alignment**: Maintains center positioning across all states

### 🗂️ Widgets & Panels
<div align="center">
   <img src="https://github.com/Ebullioscopic/DynamicIsland/blob/main/DynamicIslandSamples/clipboardpanel.png" alt="Clipboard Panel" width="350"/>
   <br>
   <img src="https://github.com/Ebullioscopic/DynamicIsland/blob/main/DynamicIslandSamples/clipboardpopover.png" alt="Clipboard Popover" width="350"/>
</div>

- **Clipboard Manager**: Quick access to recent clipboard items
- **Weather Widget**: Displays current weather (location access required)
- **App Switcher**: Swipe gestures for fast app switching

---

## 🚀 Getting Started

### Prerequisites
- **macOS Sonoma 14.0+** (Optimized for Sequoia 15.0+)
- **MacBook with Notch** (Pro 14"/16" M1/M2/M3 series)
- **Xcode 15.0+**, **Swift 5.9+**
- **Admin privileges** for system monitoring features

### Installation
```bash
git clone https://github.com/Ebullioscopic/DynamicIsland.git
cd DynamicIsland
open DynamicIsland.xcodeproj
```
1. Enable **Accessibility**, **Screen Recording**, and **Full Disk Access** in System Settings
2. Build and run in Xcode (`Cmd + R`)
3. The app will appear in your menu bar and activate the notch

---

## 📖 Usage

### Basic Controls
- **Hover to Activate**: Move cursor near the notch to expand
- **Click to Open**: Tap the notch area for full controls
- **Gesture Support**: Swipe down to expand, swipe up to close
- **Tab Navigation**: Switch between Home, Shelf, Timer, Stats, ColorPicker, and more

### System Monitoring
- **Stats Tab**: CPU, Memory, GPU, Network, Disk with live graphs
- **Layout Intelligence**: 1-3 graphs in a row, 4 in 2×2 grid, 5 in 3+2 layout
- **Smooth Transitions**: Animated layout changes, perfect centering

### ColorPicker
- **Panel & Popover**: Pick colors anywhere, see recent colors, copy formats
- **Shortcut**: Cmd+Shift+P to open picker

### Clipboard & Widgets
- **Clipboard Panel**: Access recent clipboard items
- **Weather Widget**: Current weather in notch (location access required)
- **App Switcher**: Swipe to switch apps

### Customization
- **Preferences Pane**: Long-press notch to open
- **Themes**: Light, dark, system adaptive
- **Widget Settings**: Enable/disable, adjust sizes, display preferences
- **Gestures**: Customize swipe, tap, long-press actions

---

## ⚙️ Configuration

### Settings Categories
- **Stats**: Enable/disable CPU, Memory, GPU, Network, Disk monitoring
- **Music & Media**: Visualizer type, color adaptation, media sources
- **Timer**: Default duration, notification style, colors, auto-start
- **Appearance & Behavior**: Theme, hover sensitivity, animation speed, corner radius, shadow effects
- **Multi-Display Support**: Choose main monitor, show on all displays
- **Keyboard Shortcuts**: Toggle DynamicIsland, open settings, quick stats, timer control

---

## 🚧 Roadmap

### 🔄 Upcoming Features
- **Enhanced Calendar Integration**: Weekly/monthly views, event details
- **Weather Widget**: Location-based forecasts, beautiful animations
- **Custom Shortcuts**: User-defined quick actions, app launchers
- **Performance Optimizations**: Reduced memory/battery usage
- **Voice Commands**: Siri integration
- **Widget Marketplace**: Community custom widgets
- **Advanced Analytics**: Historical performance data
- **Cloud Sync**: Settings across devices
- **AI-Powered Insights**: Intelligent system recommendations
- **3D Animations**: Enhanced visual effects
- **Plugin Architecture**: Third-party extensions
- **Cross-Platform**: iPad/iPhone companion apps

---

## 🔧 Troubleshooting

### Common Issues & Solutions
- **Permissions**: Enable Accessibility, Screen Recording, Full Disk Access
- **Stats Not Updating**: Check feature toggles, restart monitoring, verify permissions
- **Music Controls Not Working**: Ensure media app is playing, check permissions, restart app
- **Performance Issues**: Reduce update frequency, disable unused features, restart app

### Advanced
- **Reset to Defaults**:
   ```bash
   defaults delete com.ebullioscopic.DynamicIsland
   ```
- **Clean Reinstall**:
   1. Quit DynamicIsland
   2. Delete app from Applications
   3. Remove settings: `~/Library/Preferences/com.ebullioscopic.DynamicIsland.plist`
   4. Reinstall from latest build
- **Debug Mode**: Hold `⌥` while opening Settings → Advanced → Debug Mode → Enable Verbose Logging

---

## 🤝 Contributing

We welcome contributions from developers, designers, and users!

### For Developers
1. **Fork the repository**
2. **Clone your fork**
    ```bash
    git clone https://github.com/yourusername/DynamicIsland.git
    cd DynamicIsland
    ```
3. **Install dev dependencies**
    ```bash
    brew install swiftlint
    brew install swiftformat
    ```
4. **Create a feature branch**
    ```bash
    git checkout -b feature/your-feature-name
    ```
5. **Commit & Push**
    ```bash
    git commit -m "feat: add new feature"
    git push origin feature/your-feature-name
    ```
6. **Open a Pull Request**

### For Designers
- UI/UX improvements, icon design, animation concepts

### For Documentation
- User guides, API docs, translations

---

## 📜 License

This project is licensed under the **MIT License** — see [LICENSE](LICENSE) for details.

---

## 🏆 Acknowledgments

- **Apple's Dynamic Island** — inspiration for this project
- **NotchNook & HiDock** — early notch customization pioneers
- **SwiftUI, Combine, AVFoundation, IOKit** — technical foundation
- **Lottie, SF Symbols, Apple Design Resources** — design & animation
- **Open Source Contributors, Beta Testers, Community**

---

## 👥 Contributors

<table>
   <tr>
      <td align="center">
         <a href="https://github.com/Ebullioscopic">
            <img src="https://github.com/Ebullioscopic.png" width="100px;" alt="Ebullioscopic"/>
            <br />
            <sub><b>Ebullioscopic</b></sub>
         </a>
         <br />
         <sub>🚀 Creator & Lead Developer</sub>
         <br />
         <sub>Core architecture, UI/UX design</sub>
      </td>
   </tr>
</table>

---

<div align="center">
   <b>⭐ Star this repository if DynamicIsland enhanced your Mac experience!</b>
   <br><br>
   <a href="https://github.com/Ebullioscopic/DynamicIsland">🔗 GitHub Project</a>
</div>

## 🎬 Preview

![DynamicIsland Preview](https://github.com/Ebullioscopic/DynamicIsland/blob/main/dynamic-island-preview.jpeg)

## 🚀 Demonstration

![DynamicIsland Demo](https://github.com/Ebullioscopic/DynamicIsland/blob/main/dynamic-island-demo.gif)

<details open>
<summary>📑 Table of Contents</summary>

- [✨ Features](#-features)
- [🆕 What's New](#-whats-new)
- [🎥 Demo](#-demo)
- [🚀 Getting Started](#-getting-started)
  - [Prerequisites](#prerequisites)
  - [Installation](#installation)
- [📖 Usage](#-usage)
  - [Basic Controls](#basic-controls)
  - [System Monitoring](#system-monitoring)
  - [Customization Options](#customization-options)
- [⚙️ Configuration](#️-configuration)
- [🚧 Roadmap](#-roadmap)
- [🔧 Troubleshooting](#-troubleshooting)
- [🤝 Contributing](#-contributing)
- [📜 License](#-license)
- [🏆 Acknowledgments](#-acknowledgments)
- [👥 Contributors](#-contributors)

</details>

---

## ✨ Features

### 🎵 **Music & Media Controls**
- **Live Music Activity**: Real-time album art, track info, and playback controls
- **Audio Visualizer**: Dynamic spectrum visualization with color adaptation
- **Multi-Platform Support**: Works with Apple Music, Spotify, YouTube Music, and more
- **Smooth Transitions**: Elegant animations between tracks and states

### 📊 **Advanced System Monitoring**
- **Real-Time Performance Stats**: CPU, Memory, GPU usage with live graphs
- **Network Activity**: Upload/download monitoring with dual-quadrant visualization
- **Disk I/O Tracking**: Read/write speeds with real-time data
- **Intelligent Layout**: Vertical expansion for 4+ graphs with optimized spacing
- **Customizable Visibility**: Toggle individual graphs on/off
- **Smooth Animations**: Debounced updates prevent conflicts and ensure fluid transitions

### ⏱️ **Timer & Productivity**
- **Multiple Timers**: Create and manage multiple named timers
- **Live Activities**: Background timer monitoring with notifications
- **Custom Colors**: Personalize timer appearance
- **Quick Access**: Direct timer controls from the notch

### 🔋 **Battery & System Status**
- **Intelligent Battery Alerts**: Smart notifications for charging states
- **Power Management**: Low battery warnings and charging status
- **System Integration**: Native macOS battery monitoring

### 🎨 **Modern UI & Animations**
- **Smooth Transitions**: Professionally animated state changes
- **Hover Effects**: Interactive feedback with haptic support
- **Gesture Controls**: Swipe to open/close, tap interactions
- **Adaptive Sizing**: Dynamic height expansion for complex content
- **Perfect Alignment**: Maintains center positioning across all states

## 🆕 What's New

### **Enhanced Stats Feature**
- ✅ **Vertical Expansion Layout**: No more horizontal stretching - stats expand downward naturally
- ✅ **5-Graph Support**: CPU, Memory, GPU, Network, and Disk monitoring
- ✅ **Dual-Quadrant Graphs**: Network and disk stats show upload/download or read/write in split views
- ✅ **Smart Layout System**: 1-3 graphs in single row, 4 graphs in 2×2 grid, 5 graphs in 3+2 layout
- ✅ **Smooth Animations**: Debounced updates eliminate jarring transitions
- ✅ **Individual Controls**: Toggle each graph type independently
- ✅ **Perfect Centering**: Maintains alignment across all display configurations

## 🎥 Demo

Experience **DynamicIsland** in action with our comprehensive demo showcasing:
- **Smooth vertical expansion** for system stats
- **Real-time performance monitoring** with live graphs
- **Seamless music integration** with album art and controls
- **Intelligent layout transitions** between different content types

![DynamicIsland Demo](https://github.com/Ebullioscopic/DynamicIsland/raw/main/demo.gif)

---

## 🚀 Getting Started

Get **DynamicIsland** running on your macOS system with these simple steps.

### Prerequisites

- **macOS Sonoma 14.0** or later (optimized for macOS Sequoia 15.0+)
- **MacBook with Notch** (MacBook Pro 14"/16" M1 Pro/Max/M2/M3 series)
- **Xcode 15.0** or later
- **Swift 5.9** or later
- **Admin privileges** for system monitoring features

### Installation

1. **Clone the Repository**
   ```bash
   git clone https://github.com/Ebullioscopic/DynamicIsland.git
   cd DynamicIsland
   ```

2. **Open in Xcode**
   ```bash
   open DynamicIsland.xcodeproj
   ```

3. **Configure Permissions**
   - Enable **Accessibility** permissions in System Settings
   - Allow **Screen Recording** for proper notch integration
   - Grant **Full Disk Access** for system monitoring features

4. **Build and Run**
   - Select your Mac as the target device
   - Press `Cmd + R` to build and run
   - The app will appear in your menu bar and activate the notch

---

## 📖 Usage

**DynamicIsland** provides an intuitive interface that adapts to your workflow needs.

### Basic Controls

- **Hover to Activate**: Move your cursor near the notch to expand the interface
- **Click to Open**: Tap the notch area to access full controls
- **Gesture Support**: Swipe down to expand, swipe up to close
- **Tab Navigation**: Switch between Home, Shelf, Timer, and Stats tabs

### System Monitoring

#### **Stats Tab Features**
- **CPU Usage**: Real-time processor utilization with historical graph
- **Memory Stats**: RAM usage tracking with pressure indicators  
- **GPU Monitoring**: Graphics processor load for intensive tasks
- **Network Activity**: Live upload/download speeds with dual visualization
- **Disk I/O**: Read/write operations monitoring for storage performance

#### **Layout Intelligence**
- **1-3 Graphs**: Single row layout for minimal overhead
- **4 Graphs**: 2×2 quadrant arrangement for balanced viewing
- **5 Graphs**: 3+2 optimized layout with centered bottom row
- **Smooth Transitions**: Animated layout changes with perfect centering

### Customization Options

#### **Stats Configuration**
1. Navigate to **Settings → Stats**
2. **Enable/Disable Graphs**: Toggle individual monitoring features
3. **Update Frequency**: Adjust refresh rates for performance optimization
4. **Visual Preferences**: Customize colors and graph styles

#### **General Settings**
1. **Appearance**: Choose system theme or custom colors
2. **Behavior**: Configure hover sensitivity and auto-close timing
3. **Gestures**: Enable/disable swipe controls and haptic feedback
4. **Display**: Multi-monitor support and positioning options

---

## 📖 Usage

Once **DynamicIsland** is installed and running, it will display widgets and controls in the MacBook's notch area. Here are some usage tips and customization options.

### Basic Controls

- **Music Controls**: Hover over the notch and use on-screen buttons to control playback.
- **Battery Status**: A battery indicator will be displayed in the notch. Low battery alerts will appear automatically.
- **Weather Widget**: Displays current weather for your location (requires location access).
- **App Switcher**: Swipe gestures allow you to quickly switch between open applications.

### Customization Options

To personalize your DynamicIsland experience:

1. **Open Preferences**: Access the Preferences pane by long-pressing on the notch area.
2. **Themes**: Choose between **light**, **dark**, or **system adaptive** themes.
3. **Widget Settings**: Enable/disable specific widgets, adjust sizes, and set display preferences.
4. **Gestures**: Customize swipe, tap, and long-press actions for app switching and widget controls.

---

## ⚙️ Configuration

**DynamicIsland** offers extensive customization through its intuitive settings interface.

### Settings Categories

#### **📊 Stats Configuration**
```swift
// Enable/disable individual monitoring features
CPU Monitoring: ✅ Enabled
Memory Tracking: ✅ Enabled  
GPU Monitoring: ✅ Enabled
Network Activity: ✅ Enabled
Disk I/O Monitoring: ✅ Enabled
```

#### **🎵 Music & Media**
- **Visualizer Type**: Spectrum analyzer or Lottie animations
- **Color Adaptation**: Dynamic colors based on album art
- **Live Activity**: Background playback monitoring
- **Media Sources**: Apple Music, Spotify, YouTube Music support

#### **⏱️ Timer & Productivity**
- **Default Timer Duration**: Customizable presets
- **Notification Style**: Banner, alert, or silent
- **Timer Colors**: Personal color schemes
- **Auto-start Options**: Quick timer creation

#### **🎨 Appearance & Behavior**
- **Theme**: System, light, dark, or custom
- **Hover Sensitivity**: Adjust activation distance
- **Animation Speed**: Control transition timing
- **Corner Radius**: Customize notch appearance
- **Shadow Effects**: Enable/disable depth effects

### Advanced Settings

#### **🖥️ Multi-Display Support**
- **Primary Display**: Choose main monitor for the notch
- **Show on All Displays**: Extend to multiple screens
- **Display Switching**: Automatic adaptation to external monitors

#### **⌨️ Keyboard Shortcuts**
- **Toggle DynamicIsland**: `⌘ + ⌥ + D`
- **Open Settings**: `⌘ + ,`
- **Quick Stats**: `⌘ + ⌥ + S`
- **Timer Control**: `⌘ + ⌥ + T`

---

## 🚧 Roadmap

Exciting features planned for upcoming releases:

### **🔄 Version 2.1 (Next Release)**
- [ ] **Enhanced Calendar Integration**: Weekly/monthly views with event details
- [ ] **Weather Widget**: Location-based forecasts with beautiful animations
- [ ] **Custom Shortcuts**: User-defined quick actions and app launchers
- [ ] **Performance Optimizations**: Reduced memory footprint and battery usage

### **🚀 Version 2.2 (Future)**
- [ ] **Voice Commands**: Siri integration for hands-free control
- [ ] **Widget Marketplace**: Community-created custom widgets
- [ ] **Advanced Analytics**: Historical performance data and trends
- [ ] **Cloud Sync**: Settings synchronization across devices

### **🌟 Version 3.0 (Vision)**
- [ ] **AI-Powered Insights**: Intelligent system recommendations
- [ ] **3D Animations**: Enhanced visual effects with depth
- [ ] **Plugin Architecture**: Third-party developer extensions
- [ ] **Cross-Platform**: iPad and iPhone companion apps

---

## 🔧 Troubleshooting

### Common Issues & Solutions

#### **🚫 Permissions & Access**
**Issue**: DynamicIsland not appearing or functioning properly
**Solutions**:
- Go to **System Settings → Privacy & Security → Accessibility** and enable DynamicIsland
- Enable **Screen Recording** permissions for notch integration
- Grant **Full Disk Access** for system monitoring features
- Restart the app after granting permissions

#### **📊 Stats Not Updating**
**Issue**: Performance graphs showing no data or frozen
**Solutions**:
- Check that **Stats Feature** is enabled in Settings
- Verify individual graph toggles are enabled
- Restart the monitoring service: Settings → Stats → Restart Monitoring
- Ensure app has necessary system access permissions

#### **🎵 Music Controls Not Working**
**Issue**: Music widget not responding or showing incorrect information
**Solutions**:
- Verify media app is actively playing (Apple Music, Spotify, etc.)
- Check **Music & Media** permissions in System Settings
- Restart the music application
- Toggle **Live Activity** setting in DynamicIsland preferences

#### **⚡ Performance Issues**
**Issue**: High CPU usage or slow animations
**Solutions**:
- Reduce stats update frequency: Settings → Stats → Update Interval
- Disable unused monitoring features to reduce overhead
- Close unnecessary background applications
- Restart DynamicIsland if memory usage is high

### Advanced Troubleshooting

#### **🔧 Reset to Defaults**
```bash
# Reset all settings to factory defaults
defaults delete com.ebullioscopic.DynamicIsland
```

#### **📱 Clean Reinstall**
1. Quit DynamicIsland completely
2. Delete app from Applications folder
3. Remove settings: `~/Library/Preferences/com.ebullioscopic.DynamicIsland.plist`
4. Reinstall from latest build

#### **🐛 Debug Mode**
Enable detailed logging for troubleshooting:
1. Hold `⌥` while opening Settings
2. Navigate to **Advanced → Debug Mode**
3. Enable **Verbose Logging**
4. Reproduce the issue and check Console.app for detailed logs

### **💬 Getting Help**
- **GitHub Issues**: Report bugs or request features
- **Discussions**: Community support and tips
- **Documentation**: Detailed guides and API reference

---

## 🤝 Contributing

We welcome contributions from developers, designers, and users alike!

### **🛠️ For Developers**

#### **Setting Up Development Environment**
1. **Fork the Repository**
2. **Clone Your Fork**:
   ```bash
   git clone https://github.com/yourusername/DynamicIsland.git
   cd DynamicIsland
   ```
3. **Install Development Dependencies**:
   ```bash
   # SwiftLint for code formatting
   brew install swiftlint
   
   # SwiftFormat for consistent styling
   brew install swiftformat
   ```

#### **Development Workflow**
1. **Create Feature Branch**:
   ```bash
   git checkout -b feature/your-feature-name
   ```
2. **Follow Code Standards**:
   - Use SwiftUI best practices
   - Follow Apple's Human Interface Guidelines
   - Add comprehensive comments for complex logic
   - Include unit tests for new functionality

3. **Commit Guidelines**:
   ```bash
   git commit -m "feat: add network monitoring graphs
   
   - Implement dual-quadrant visualization
   - Add upload/download speed tracking
   - Include BSD socket integration
   - Update settings UI for new feature"
   ```

4. **Push and Create PR**:
   ```bash
   git push origin feature/your-feature-name
   ```

### **🎨 For Designers**
- **UI/UX Improvements**: Mockups and design suggestions
- **Icon Design**: System icons and app branding
- **Animation Concepts**: Motion design for smooth interactions

### **📚 For Documentation**
- **User Guides**: Step-by-step tutorials
- **API Documentation**: Technical reference materials
- **Translations**: Localization for international users

### **Code Review Process**
1. All PRs require review from core maintainers
2. Automated testing must pass (CI/CD pipeline)
3. Code coverage should not decrease significantly
4. Follow semantic versioning for releases

## 🤝 Contributing

We welcome contributions from the community! Follow the steps below to contribute:

1. **Fork the repository**.
2. **Clone Your Fork**:
    ```bash
    git clone https://github.com/yourusername/DynamicIsland.git
    cd DynamicIsland
    ```
3. **Create a New Branch**:
    ```bash
    git checkout -b feature/YourFeatureName
    ```
4. **Make Your Changes** and **Commit**:
    ```bash
    git commit -m "Added new feature"
    ```
5. **Push to Your Fork**:
    ```bash
    git push origin feature/YourFeatureName
    ```
6. **Create a Pull Request**: Head to the original repository and open a pull request.

For major changes, please open an issue first to discuss what you’d like to change.

---

## 📜 License

This project is licensed under the **MIT License** - see the [LICENSE](LICENSE) file for complete details.

### **License Summary**
- ✅ **Commercial Use**: Use in commercial projects
- ✅ **Modification**: Modify and adapt the code
- ✅ **Distribution**: Share and redistribute
- ✅ **Private Use**: Use for personal projects
- ❗ **Attribution Required**: Credit the original authors

---

## 🏆 Acknowledgments

**DynamicIsland** exists thanks to the contributions and inspiration from:

### **🎯 Core Inspiration**
- **BoringNotch**: The base project on which DynamicIsland is built on
- **Apple's Dynamic Island**: The innovative hardware feature that inspired this software implementation
- **NotchNook & HiDock**: Early notch customization pioneers
- **macOS Design Principles**: Following Apple's human interface guidelines

### **🛠️ Technical Foundation**
- **SwiftUI Framework**: For modern, reactive user interfaces
- **Combine Framework**: Reactive programming and data flow
- **AVFoundation**: Audio processing and media integration
- **IOKit**: Low-level system monitoring capabilities

### **🎨 Design & Animation**
- **Lottie by Airbnb**: Beautiful animations and micro-interactions
- **SF Symbols**: Consistent iconography throughout the app
- **Apple Design Resources**: Color palettes and spacing guidelines

### **🌟 Community**
- **Open Source Contributors**: Everyone who submitted code, bug reports, and feature requests
- **Beta Testers**: Early adopters who helped refine the experience
- **Design Feedback**: UI/UX suggestions from the community

### **📚 Educational Resources**
- **Stanford CS193p**: SwiftUI development techniques
- **Apple WWDC Sessions**: Best practices and new framework features
- **Ray Wenderlich Tutorials**: Advanced iOS/macOS development patterns

---

## 👥 Contributors

Meet the team behind **DynamicIsland**:

<table>
  <tr>
    <td align="center">
      <a href="https://github.com/Ebullioscopic">
        <img src="https://github.com/Ebullioscopic.png" width="100px;" alt="Ebullioscopic"/>
        <br />
        <sub><b>Ebullioscopic</b></sub>
      </a>
      <br />
      <sub>🚀 Creator & Lead Developer</sub>
      <br />
      <sub>Core architecture, UI/UX design</sub>
    </td>
  </tr>
</table>

### **🌟 Special Recognition**

#### **📊 Stats Feature Development**
- **System Monitoring**: Advanced CPU, Memory, GPU tracking
- **Network Analytics**: Real-time upload/download visualization  
- **Vertical Layout System**: Intelligent graph arrangement
- **Performance Optimization**: Debounced updates and smooth animations

#### **🎵 Music Integration**
- **Multi-Platform Support**: Apple Music, Spotify, YouTube Music
- **Audio Visualization**: Real-time spectrum analysis
- **Live Activities**: Background playback monitoring

#### **⚡ Performance & Reliability**
- **Memory Management**: Efficient resource utilization
- **Animation System**: Smooth, conflict-free transitions
- **Error Handling**: Robust system with graceful degradation

---

<div align="center">

### **⭐ Star this repository if DynamicIsland enhanced your Mac experience!**

### **🔗 Connect with the Project**
[![GitHub Stars](https://img.shields.io/github/stars/Ebullioscopic/DynamicIsland?style=social)](https://github.com/Ebullioscopic/DynamicIsland/stargazers)
[![GitHub Forks](https://img.shields.io/github/forks/Ebullioscopic/DynamicIsland?style=social)](https://github.com/Ebullioscopic/DynamicIsland/network/members)
[![GitHub Issues](https://img.shields.io/github/issues/Ebullioscopic/DynamicIsland)](https://github.com/Ebullioscopic/DynamicIsland/issues)
[![GitHub Pull Requests](https://img.shields.io/github/issues-pr/Ebullioscopic/DynamicIsland)](https://github.com/Ebullioscopic/DynamicIsland/pulls)

**Built with ❤️ for the macOS community**

</div>