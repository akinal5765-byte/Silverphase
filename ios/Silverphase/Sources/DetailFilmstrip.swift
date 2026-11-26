import ImageIO
import SwiftUI
import UIKit

/// Gallery thumbnail navigation: native momentum, a fixed center target, and
/// visual emphasis that never changes the collection's layout geometry.
struct DetailFilmstrip: UIViewRepresentable {
    struct Item: Equatable {
        let id: UUID
        let name: String
        let previewURL: URL
        let sourceURL: URL
        let version: Int
    }

    let items: [Item]
    let selection: UUID
    let reduceMotion: Bool
    let onScrubbing: (Bool) -> Void
    let onSelect: (UUID, CGImage?) -> Void

    private static let itemWidth: CGFloat = 36
    private static let itemHeight: CGFloat = 54
    private static let spacing: CGFloat = 2
    private static let cellIdentifier = "gallery-filmstrip"

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> UICollectionView {
        let layout = UICollectionViewFlowLayout()
        layout.scrollDirection = .horizontal
        layout.itemSize = CGSize(width: Self.itemWidth, height: Self.itemHeight)
        layout.minimumLineSpacing = Self.spacing
        layout.minimumInteritemSpacing = 0

        let view = StripCollectionView(frame: .zero, collectionViewLayout: layout)
        view.backgroundColor = .clear
        view.showsHorizontalScrollIndicator = false
        view.contentInsetAdjustmentBehavior = .never
        view.decelerationRate = .normal
        view.scrollsToTop = false
        view.alwaysBounceHorizontal = items.count > 1
        if #available(iOS 26.0, *) {
            view.topEdgeEffect.isHidden = true
            view.bottomEdgeEffect.isHidden = true
        }
        view.register(ThumbnailCell.self, forCellWithReuseIdentifier: Self.cellIdentifier)
        view.dataSource = context.coordinator
        view.delegate = context.coordinator
        view.accessibilityIdentifier = "photo-detail.filmstrip"
        view.isAccessibilityElement = false

        let coordinator = context.coordinator
        coordinator.view = view
        view.onViewportChange = { [weak coordinator] in coordinator?.viewportChanged() }
        return view
    }

    func updateUIView(_ view: UICollectionView, context: Context) {
        context.coordinator.update(items: items, selection: selection, reduceMotion: reduceMotion,
                                   onScrubbing: onScrubbing, onSelect: onSelect)
    }

    final class Coordinator: NSObject, UICollectionViewDataSource, UICollectionViewDelegate {
        weak var view: UICollectionView?
        private var items: [Item] = []
        private var itemIndexes: [UUID: Int] = [:]
        private var selected: UUID?
        private var onSelect: ((UUID, CGImage?) -> Void)?
        private var onScrubbing: ((Bool) -> Void)?
        private var isScrubbing = false
        private var lastBinding: UUID?
        private var reduceMotion = false
        private var programmatic = false
        private var layoutUpdate = false

        func update(items newItems: [Item], selection: UUID, reduceMotion: Bool,
                    onScrubbing: @escaping (Bool) -> Void, onSelect: @escaping (UUID, CGImage?) -> Void) {
            guard let view else { return }
            self.onSelect = onSelect
            self.onScrubbing = onScrubbing
            view.alwaysBounceHorizontal = newItems.count > 1
            self.reduceMotion = reduceMotion
            if items != newItems {
                if items.map(\.id) == newItems.map(\.id) {
                    let previous = items
                    items = newItems
                    // No reload is needed when only the edited thumbnail changes.
                    for index in view.indexPathsForVisibleItems where previous[index.item] != items[index.item] {
                        configure(view.cellForItem(at: index) as? ThumbnailCell, at: index)
                    }
                } else {
                    let old = layoutUpdate
                    layoutUpdate = true
                    items = newItems
                    itemIndexes = Dictionary(uniqueKeysWithValues: newItems.enumerated().map { ($0.element.id, $0.offset) })
                    selected = selection
                    programmatic = false
                    view.reloadData()
                    viewportChanged()
                    layoutUpdate = old
                }
            }
            // User-driven scrubbing is the source of truth until UIKit
            // settles. A representable update can contain an older binding
            // while the pan delegate is still in the same run-loop turn.
            if selection != lastBinding {
                lastBinding = selection
                if !isScrubbing, selection != selected {
                    selected = selection
                    align(selection, animated: true)
                }
            }
            updateVisibleEffects()
        }

        func viewportChanged() {
            guard let view, view.bounds.width > 0 else { return }
            let old = layoutUpdate
            layoutUpdate = true
            defer { layoutUpdate = old }
            let padding = max(0, (view.bounds.width - DetailFilmstrip.itemWidth) / 2)
            let insets = UIEdgeInsets(top: 0, left: padding, bottom: 0, right: padding)
            if view.contentInset != insets { view.contentInset = insets }
            view.layoutIfNeeded()
            if !view.isTracking, !view.isDragging, !view.isDecelerating, let selected {
                align(selected, animated: false)
            }
            updateVisibleEffects()
        }

        private func indexNearest(to center: CGFloat) -> Int? {
            guard let view, !items.isEmpty else { return nil }
            let radius = DetailFilmstrip.itemWidth * 2
            let region = CGRect(x: center - radius, y: 0, width: radius * 2, height: view.bounds.height)
            return view.collectionViewLayout.layoutAttributesForElements(in: region)?
                .filter { $0.representedElementCategory == .cell }
                .min { abs($0.center.x - center) < abs($1.center.x - center) }?
                .indexPath.item
        }

        private func offset(for index: Int) -> CGFloat? {
            guard let view, let center = view.collectionViewLayout
                .layoutAttributesForItem(at: IndexPath(item: index, section: 0))?.center.x else { return nil }
            let minimum = -view.adjustedContentInset.left
            let maximum = max(minimum, view.contentSize.width - view.bounds.width + view.adjustedContentInset.right)
            return min(maximum, max(minimum, center - view.bounds.width / 2))
        }

        private func align(_ id: UUID, animated: Bool) {
            guard let view, let index = itemIndexes[id], let x = offset(for: index) else { return }
            guard abs(view.contentOffset.x - x) > 0.5 else {
                updateVisibleEffects()
                return
            }
            programmatic = animated && !reduceMotion && view.window != nil
            view.setContentOffset(CGPoint(x: x, y: view.contentOffset.y), animated: programmatic)
            updateVisibleEffects()
        }

        private func select(_ id: UUID) {
            guard selected != id else { return }
            selected = id
            lastBinding = id
            let index = itemIndexes[id].map { IndexPath(item: $0, section: 0) }
            let cell = index.flatMap { view?.cellForItem(at: $0) as? ThumbnailCell }
            onSelect?(id, cell?.preview)
        }

        private func choose(_ id: UUID) {
            select(id)
            align(id, animated: true)
            updateVisibleEffects()
        }

        func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int { items.count }

        func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
            let cell = collectionView.dequeueReusableCell(withReuseIdentifier: DetailFilmstrip.cellIdentifier, for: indexPath)
            configure(cell as? ThumbnailCell, at: indexPath)
            return cell
        }

        private func configure(_ cell: ThumbnailCell?, at indexPath: IndexPath) {
            guard let cell, items.indices.contains(indexPath.item) else { return }
            let item = items[indexPath.item]
            cell.configure(item)
            cell.activate = { [weak self] in self?.choose(item.id) }
            applyEffects(to: cell, at: indexPath)
        }

        func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
            guard items.indices.contains(indexPath.item) else { return }
            choose(items[indexPath.item].id)
        }

        func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
            programmatic = false
            if !isScrubbing {
                isScrubbing = true
                onScrubbing?(true)
            }
        }

        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            guard !layoutUpdate else { return }
            if isScrubbing, !programmatic {
                let center = scrollView.contentOffset.x + scrollView.bounds.width / 2
                if let index = indexNearest(to: center), items.indices.contains(index) { select(items[index].id) }
            }
            updateVisibleEffects()
        }

        func scrollViewWillEndDragging(_ scrollView: UIScrollView, withVelocity velocity: CGPoint,
                                       targetContentOffset: UnsafeMutablePointer<CGPoint>) {
            let center = targetContentOffset.pointee.x + scrollView.bounds.width / 2
            if let index = indexNearest(to: center), let x = offset(for: index) {
                targetContentOffset.pointee.x = x
            }
        }

        func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) { settle(scrollView) }

        func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
            if !decelerate { settle(scrollView) }
        }

        func scrollViewDidEndScrollingAnimation(_ scrollView: UIScrollView) {
            programmatic = false
            updateVisibleEffects()
        }

        private func settle(_ scrollView: UIScrollView) {
            if let index = indexNearest(to: scrollView.contentOffset.x + scrollView.bounds.width / 2),
               items.indices.contains(index) {
                let id = items[index].id
                select(id)
                align(id, animated: true)
            }
            if isScrubbing {
                isScrubbing = false
                onScrubbing?(false)
            }
        }

        private func updateVisibleEffects() {
            guard let view else { return }
            for cell in view.visibleCells {
                if let cell = cell as? ThumbnailCell, let index = view.indexPath(for: cell) {
                    applyEffects(to: cell, at: index)
                }
            }
        }

        private func applyEffects(to cell: ThumbnailCell, at index: IndexPath) {
            guard let view, items.indices.contains(index.item) else { return }
            let center = view.contentOffset.x + view.bounds.width / 2
            let itemCenter = cell.center.x
            let distance = min(1, abs(itemCenter - center) / DetailFilmstrip.itemWidth)
            cell.apply(emphasis: reduceMotion ? 0 : (1 - distance), selected: items[index.item].id == selected)
        }
    }

    private final class StripCollectionView: UICollectionView {
        var onViewportChange: (() -> Void)?
        private var viewport = CGSize.zero

        override func layoutSubviews() {
            super.layoutSubviews()
            guard bounds.size != viewport, bounds.width > 0 else { return }
            viewport = bounds.size
            onViewportChange?()
        }
    }

    private final class ThumbnailCell: UICollectionViewCell {
        private let artwork = UIView()
        private let selectionMark = UIView()
        private let imageView = UIImageView()
        private var item: Item?
        private var load: Task<Void, Never>?
        var activate: (() -> Void)?
        var preview: CGImage? { imageView.image?.cgImage }

        override init(frame: CGRect) {
            super.init(frame: frame)
            artwork.backgroundColor = .tertiarySystemFill
            artwork.layer.cornerRadius = 5
            artwork.layer.cornerCurve = .continuous
            artwork.clipsToBounds = true
            imageView.contentMode = .scaleAspectFill
            artwork.addSubview(imageView)
            contentView.addSubview(artwork)
            selectionMark.backgroundColor = .systemOrange
            selectionMark.layer.cornerRadius = 1
            selectionMark.isUserInteractionEnabled = false
            selectionMark.isHidden = true
            contentView.addSubview(selectionMark)
            isAccessibilityElement = true
            accessibilityTraits = .button
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        override func layoutSubviews() {
            super.layoutSubviews()
            artwork.bounds = CGRect(origin: .zero, size: CGSize(width: contentView.bounds.width, height: contentView.bounds.height - 8))
            artwork.center = CGPoint(x: contentView.bounds.midX, y: artwork.bounds.height / 2 + 1)
            imageView.frame = artwork.bounds
            selectionMark.frame = CGRect(x: contentView.bounds.midX - 6, y: contentView.bounds.maxY - 3,
                                         width: 12, height: 2)
        }

        override func prepareForReuse() {
            super.prepareForReuse()
            load?.cancel()
            load = nil
            item = nil
            activate = nil
            imageView.image = nil
        }

        func configure(_ item: Item) {
            accessibilityLabel = item.name
            accessibilityIdentifier = "photo-detail.thumb.\(item.id)"
            guard item != self.item else { return }
            let samePhoto = item.id == self.item?.id
            self.item = item
            load?.cancel()
            if !samePhoto { imageView.image = nil }
            load = Task(priority: .utility) { [weak self] in
                let image = await DetailFilmstripImageCache.shared.image(for: item)
                guard let self, !Task.isCancelled, self.item == item, let image else { return }
                self.imageView.image = UIImage(cgImage: image)
            }
        }

        func apply(emphasis: CGFloat, selected: Bool) {
            let scale = selected ? 1 : 0.94 + 0.02 * emphasis
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            artwork.transform = CGAffineTransform(scaleX: scale, y: scale)
            selectionMark.isHidden = !selected
            CATransaction.commit()
            let traits: UIAccessibilityTraits = selected ? [.button, .selected] : .button
            if traits != accessibilityTraits { accessibilityTraits = traits }
        }

        override func accessibilityActivate() -> Bool {
            guard let activate else { return false }
            activate()
            return true
        }
    }
}

private actor DetailFilmstripImageCache {
    static let shared = DetailFilmstripImageCache()
    private let cache = NSCache<NSString, CGImage>()

    init() { cache.totalCostLimit = 8 * 1024 * 1024 }

    func image(for item: DetailFilmstrip.Item) -> CGImage? {
        guard !Task.isCancelled else { return nil }
        let key = "\(item.previewURL.absoluteString)#\(item.version)" as NSString
        if let image = cache.object(forKey: key) { return image }
        return autoreleasepool {
            for url in [item.previewURL, item.sourceURL] {
                guard !Task.isCancelled else { break }
                guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary) else { continue }
                var options: [CFString: Any] = [
                    kCGImageSourceThumbnailMaxPixelSize: 144,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceShouldCacheImmediately: true
                ]
                let embedded = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
                options[kCGImageSourceCreateThumbnailFromImageIfAbsent] = true
                if let image = embedded ?? CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) {
                    cache.setObject(image, forKey: key, cost: image.bytesPerRow * image.height)
                    return image
                }
            }
            return nil
        }
    }
}
