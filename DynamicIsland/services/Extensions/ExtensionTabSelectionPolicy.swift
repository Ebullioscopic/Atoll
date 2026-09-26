func shouldDisplayTabSelectionCapsule(
    isSelected: Bool,
    isExtensionTab: Bool,
    showExtensionBackground: Bool
) -> Bool {
    isSelected && (!isExtensionTab || showExtensionBackground)
}
