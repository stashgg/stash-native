//
//  ViewController+CallbackChips.swift
//  StashNativeSample
//
//  Every SDK callback surfaces as a chip at the top.
//

import UIKit

extension ViewController {

    /// Safety cap; chips also auto-expire after a few seconds.
    private static let maxCallbackChips = 6
    private static let chipLifetime: TimeInterval = 5

    private static let chipTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()

    /// Every SDK callback (and deeplink outcome) surfaces the same way: a timestamped row on the
    /// top chip stack. Auto-expires after chipLifetime; tap to dismiss.
    func addCallbackChip(_ text: String) {
        let row = UIView()
        row.backgroundColor = .systemBlue
        row.layer.cornerRadius = 12

        let label = UILabel()
        label.text = text
        label.textColor = .white
        label.font = .systemFont(ofSize: 14, weight: .medium)
        label.numberOfLines = 1
        label.lineBreakMode = .byTruncatingTail
        label.setContentHuggingPriority(.defaultLow, for: .horizontal)
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let time = UILabel()
        time.text = ViewController.chipTimeFormatter.string(from: Date())
        time.textColor = UIColor.white.withAlphaComponent(0.75)
        time.font = .systemFont(ofSize: 12, weight: .regular)
        time.setContentHuggingPriority(.required, for: .horizontal)
        time.setContentCompressionResistancePriority(.required, for: .horizontal)

        let hstack = UIStackView(arrangedSubviews: [label, time])
        hstack.axis = .horizontal
        hstack.spacing = 8
        hstack.alignment = .center
        hstack.translatesAutoresizingMaskIntoConstraints = false
        row.addSubview(hstack)
        NSLayoutConstraint.activate([
            hstack.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 16),
            hstack.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -16),
            hstack.topAnchor.constraint(equalTo: row.topAnchor, constant: 12),
            hstack.bottomAnchor.constraint(equalTo: row.bottomAnchor, constant: -12)
        ])

        let tap = UITapGestureRecognizer(target: self, action: #selector(dismissChip(_:)))
        row.addGestureRecognizer(tap)

        // Newest on top; the stack grows downward and oldest falls off the bottom.
        callbackChipStack.superview?.bringSubviewToFront(callbackChipStack)
        callbackChipStack.insertArrangedSubview(row, at: 0)
        while callbackChipStack.arrangedSubviews.count > ViewController.maxCallbackChips {
            callbackChipStack.arrangedSubviews.last?.removeFromSuperview()
        }

        row.alpha = 0
        row.transform = CGAffineTransform(translationX: 0, y: -12)
        UIView.animate(withDuration: 0.22) {
            row.alpha = 1
            row.transform = .identity
            self.view.layoutIfNeeded()
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + ViewController.chipLifetime) { [weak self, weak row] in
            guard let self = self, let row = row, row.superview != nil else { return }
            self.removeChip(row)
        }
    }

    @objc private func dismissChip(_ gesture: UITapGestureRecognizer) {
        if let view = gesture.view {
            removeChip(view)
        }
    }

    /// Fades + collapses a chip, letting the stack fall into place.
    private func removeChip(_ chip: UIView) {
        UIView.animate(withDuration: 0.22, animations: {
            chip.alpha = 0
            chip.isHidden = true
            self.view.layoutIfNeeded()
        }, completion: { _ in
            chip.removeFromSuperview()
        })
    }

    /// Reaches the active sample view controller so out-of-VC callers (deeplinks) can post chips.
    static func postCallbackChip(_ text: String) {
        DispatchQueue.main.async {
            let scenes = UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
            for scene in scenes {
                for window in scene.windows {
                    if let nav = window.rootViewController as? UINavigationController,
                       let host = nav.viewControllers.first as? ViewController {
                        host.addCallbackChip(text)
                        return
                    }
                }
            }
        }
    }
}
