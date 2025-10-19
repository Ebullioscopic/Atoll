import Cocoa

class DynamicIslandStatusMenu: NSMenu {
    
    var statusItem: NSStatusItem!
    
    override init(title: String) {
        super.init(title: title)
        setupStatusItem()
    }
    
    convenience init() {
        self.init(title: "DynamicIsland")
        setupStatusItem()
    }
    
    required init(coder: NSCoder) {
        super.init(coder: coder)
        setupStatusItem()
    }
    
    private func setupStatusItem() {
        // Initialize the status item
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "music.note", accessibilityDescription: "DynamicIsland")
            button.action = #selector(showMenu)
        }
        
        // Set up the menu
        self.addItem(NSMenuItem(title: "Quit", action: #selector(quitAction), keyEquivalent: "q"))
        statusItem.menu = self
    }
    
    @objc func showMenu() {
        // Handle menu show action
    }
    
    @objc func quitAction() {
        NSApp.terminate(nil)
    }

}
