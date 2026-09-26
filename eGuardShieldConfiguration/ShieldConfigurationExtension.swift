import ManagedSettings
import ManagedSettingsUI
import UIKit

/// eGuard-branded shields. The copy tells the child plainly why the app or site is paused.
class ShieldConfigurationExtension: ShieldConfigurationDataSource {
    private static let brand = UIColor(red: 0x2F / 255, green: 0x6F / 255, blue: 0xED / 255, alpha: 1)

    override func configuration(shielding application: Application) -> ShieldConfiguration {
        make(
            title: "\(application.localizedDisplayName ?? "This app") is paused",
            subtitle: "eGuard has shielded this app under your family's protection settings."
        )
    }

    override func configuration(shielding application: Application, in category: ActivityCategory) -> ShieldConfiguration {
        make(
            title: "\(application.localizedDisplayName ?? "This app") is paused",
            subtitle: "Apps in \(category.localizedDisplayName ?? "this category") are shielded right now."
        )
    }

    override func configuration(shielding webDomain: WebDomain) -> ShieldConfiguration {
        make(
            title: "\(webDomain.domain ?? "This website") is paused",
            subtitle: "eGuard has shielded this website under your family's protection settings."
        )
    }

    override func configuration(shielding webDomain: WebDomain, in category: ActivityCategory) -> ShieldConfiguration {
        make(
            title: "\(webDomain.domain ?? "This website") is paused",
            subtitle: "Websites in \(category.localizedDisplayName ?? "this category") are shielded right now."
        )
    }

    private func make(title: String, subtitle: String) -> ShieldConfiguration {
        ShieldConfiguration(
            backgroundBlurStyle: .systemMaterial,
            backgroundColor: UIColor.systemBackground,
            icon: UIImage(systemName: "shield.lefthalf.filled"),
            title: ShieldConfiguration.Label(text: title, color: .label),
            subtitle: ShieldConfiguration.Label(text: subtitle, color: .secondaryLabel),
            primaryButtonLabel: ShieldConfiguration.Label(text: "OK", color: .white),
            primaryButtonBackgroundColor: Self.brand
        )
    }
}
