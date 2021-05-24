//
//  LoadableImageView.swift
//  NerdzUtils
//
//  Created by new user on 07.11.2020.
//

import UIKit

public enum ImageStoringPolicy {
    case none
    case cache(timeout: TimeInterval? = nil)
}

public enum LoadableImage: Equatable {
    case fromUrl(
            _ url: URL?,
            storingPolicy: ImageStoringPolicy,
            blurHash: BlurHashInfo? = nil,
            completion: ((UIImage?) -> Void)? = nil)
    
    case fromData(_ data: Data?, scale: CGFloat = 1)
    case named(_ name: String)
    case image(_ image: UIImage)
    case placeholder
    
    static public func == (lhs: LoadableImage, rhs: LoadableImage) -> Bool {
        if case .fromUrl(let lhsUrl, _, _, _) = lhs, case .fromUrl(let rhsUrl, _, _, _) = rhs {
            return lhsUrl == rhsUrl
        }
        else if case .fromData(let lhsData, let lhsScale) = lhs, case .fromData(let rhsData, let rhsScale) = rhs {
            return lhsData == rhsData && lhsScale == rhsScale
        }
        else if case .named(let lhsName) = lhs, case .named(let rhsName) = rhs {
            return lhsName == rhsName
        }
        else if case .placeholder = lhs, case .placeholder = rhs {
            return true
        }
        else {
            return false
        }
    }
}

public class LoadableImageView: UIImageView {
    typealias CacheInfo = (expirationDate: Date?, image: UIImage)
    
    private static var urlCache: [URL: CacheInfo] = [:]
    private static var blurCache: [String: CacheInfo] = [:]
    
    @IBInspectable
    public var placeholderImage: UIImage? {
        didSet {
            if case .placeholder = loadableImage {
                reload()
            }
        }
    }
    
    public lazy var loadableImage: LoadableImage = {
        if let image = image {
            return .image(image)
        }
        else {
            return .placeholder
        }
    }() {
        didSet {
            guard oldValue != loadableImage else {
                return
            }
            
            reload()
        }
    }
    
    public required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        setToDefault()
    }

    public override init(frame: CGRect) {
        super.init(frame: frame)
        setToDefault()
    }

    private func setToDefault() {
        loadableImage = .placeholder
        reload()
    }
    
    private func reload() {
        switch loadableImage {
        case .placeholder:
            image = placeholderImage
            
        case .image(let image):
            self.image = image
            
        case .named(let name):
            image = UIImage(named: name)
            
        case .fromData(let data, let scale):
            reload(with: data, scale: scale)
            
        case .fromUrl(let url, let policy, let hashInfo, let completion):
            reload(with: url, storingPolicy: policy, hashInfo: hashInfo, completion: completion)
        }
    }
    
    private func reload(with data: Data?, scale: CGFloat) {
        guard let data = data else {
            loadableImage = .placeholder
            return
        }
        
        image = UIImage(data: data, scale: scale)
    }
    
    private func setBlurHash(_ info: BlurHashInfo, storingPolicy: ImageStoringPolicy) -> Bool {
        
        if let imageInfo = type(of: self).blurCache[info.blurHash] {
            image = imageInfo.image
            return true
        }
        
        guard let image = UIImage(info: info) else {
            return false
        }
        
        self.image = image
        
        if case .cache(let timeout) = storingPolicy {
            let expirationDate = timeout.flatMap({ Date(timeInterval: $0, since: Date()) })
            type(of: self).blurCache[info.blurHash] = (expirationDate, image)
        }
        
        return true
    }
    
    private func reload(
        with url: URL?, 
        storingPolicy: ImageStoringPolicy,
        hashInfo: BlurHashInfo? = nil,
        completion: ((UIImage?) -> Void)? = nil) {
        clearExpiredCache()
        
        guard let url = url else {
            loadableImage = .placeholder
            completion?(nil)
            return
        }
        
        if let imageInfo = type(of: self).urlCache[url] {
            self.image = imageInfo.image
            completion?(imageInfo.image)
            return
        }
        
        if let hashInfo = hashInfo {
            if !setBlurHash(hashInfo, storingPolicy: storingPolicy) {
                image = placeholderImage
            }
        }
        else {
            image = placeholderImage
        }
        
        DispatchQueue.global(qos: .background).async { [weak self] in
            if let data = try? Data(contentsOf: url), let image = UIImage(data: data) {
                DispatchQueue.main.async { [weak self] in
                    guard let self = self else {
                        completion?(nil)
                        return
                    }
                    
                    if case .cache(let timeout) = storingPolicy {
                        let expirationDate = timeout.flatMap({ Date(timeInterval: $0, since: Date()) })
                        type(of: self).urlCache[url] = (expirationDate, image)
                    }
                    
                    if self.loadableImage == .fromUrl(url, storingPolicy: storingPolicy) {
                        self.image = image
                        completion?(image)
                    }
                    else {
                        completion?(nil)
                        return
                    }
                }
            }
            else {
                DispatchQueue.main.async { [weak self] in
                    self?.loadableImage = .placeholder
                    completion?(nil)
                }
            }
        }
    }
    
    private func clearExpiredCache() {
        for (key, value) in type(of: self).urlCache {
            if let expirationDate = value.expirationDate, expirationDate > Date() {
                type(of: self).urlCache.removeValue(forKey: key)
            }
        }
        
        for (key, value) in type(of: self).blurCache {
            if let expirationDate = value.expirationDate, expirationDate > Date() {
                type(of: self).blurCache.removeValue(forKey: key)
            }
        }
    }
}
