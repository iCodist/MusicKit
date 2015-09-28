//
//  KeyboardView.swift
//  Keyboard
//
//  Created by Ben Guo on 9/25/15.
//  Copyright © 2015 MusicKit. All rights reserved.
//

import UIKit

public protocol KeyboardViewDelegate: class {
    func keyboardView(keyboard: KeyboardView, addedTouches: Set<KeyboardTouch>)
    func keyboardView(keyboard: KeyboardView, changedTouches: Set<KeyboardTouch>)
    func keyboardView(keyboard: KeyboardView, removedTouches: Set<KeyboardTouch>)
}

public class KeyboardView: UIView, UIScrollViewDelegate {

    /// The keyboard's delegate
    public var delegate: KeyboardViewDelegate?

    /// The default force of the keyboard, used on devices without force
    public var defaultForce: CGFloat = 0.5

    /// The keyboard's pitches
    public var pitchSet: PitchSet = Scale.Chromatic(Chroma.C*3).extend(3) {
        didSet {
            viewModel.pitchSet = pitchSet
            updateWithPitches(pitchSet)
            setNeedsLayout()
        }
    }

    /// The keyboard's current active touches
    public var activeTouches: Set<KeyboardTouch> {
        return viewModel.activeTouches
    }

    /// The height of the scroll pad
    public var scrollPadHeight: CGFloat = 128.0 {
        didSet { setNeedsLayout() }
    }

    /// The width of white keys (mm)
    public var whiteKeyWidth: CGFloat = 20 {
        didSet { setNeedsLayout() }
    }

    /// The width of black keys relative to white keys
    public var blackKeyRelativeWidth: CGFloat = 13.7/23.5

    private lazy var viewModel: KeyboardViewModel = {
        return KeyboardViewModel(view: self)
        }()

    private var whiteKeyWidthPx: CGFloat {
        return whiteKeyWidth/UIDevice.mmPerPixel
    }

    private lazy var keyViews = [KeyView]()
    private lazy var keyContainer: UIScrollView = {
        let view = UIScrollView()
        view.scrollEnabled = false
        view.userInteractionEnabled = false
        return view
    }()
    private lazy var scrollPad: UIScrollView = {
        let view = UIScrollView()
        view.showsHorizontalScrollIndicator = false
        view.showsVerticalScrollIndicator = false
        view.delegate = self
        return view
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        load()
    }

    required public init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        load()
    }

    func load() {
        multipleTouchEnabled = true
        scrollPadHeight = whiteKeyWidthPx
        updateWithPitches(pitchSet)
        addSubview(keyContainer)
        addSubview(scrollPad)
    }

    override public func layoutSubviews() {
        super.layoutSubviews()

        let scrollPadHeight = whiteKeyWidthPx
        scrollPad.frame = CGRectMake(0, bounds.height - scrollPadHeight,
            bounds.width, scrollPadHeight)
        keyContainer.frame = CGRectMake(0, 0,
            bounds.width, CGRectGetMinY(scrollPad.frame))

        var lastMaxX: CGFloat = 0
        for i in 0..<keyViews.count {
            let view = keyViews[i]
            view.frame = CGRectMake(CGFloat(i)*whiteKeyWidthPx,
                0, whiteKeyWidthPx, bounds.height - scrollPadHeight)
            lastMaxX = CGRectGetMaxX(view.frame)
        }
        keyContainer.contentSize = CGSizeMake(lastMaxX, bounds.height)
        scrollPad.contentSize = CGSizeMake(lastMaxX, scrollPad.bounds.height)
    }

    func updateWithPitches(pitches: PitchSet) {
        for keyView in keyViews {
            keyView.removeFromSuperview()
        }
        keyViews.removeAll()
        for pitch in pitchSet {
            let keyView = KeyView(pitch: pitch)
            keyContainer.addSubview(keyView)
            keyViews.append(keyView)
        }
    }

    // MARK: Touches
    private func parsedTouches(touches: Set<UITouch>)
        -> (Set<KeyboardTouch>, [KeyView], [(KeyView, KeyboardTouch)])
    {
        var kbTouches = Set<KeyboardTouch>()
        var keyTouchTuples = [(KeyView, KeyboardTouch)]()
        var removedKeys = [KeyView]()
        for key in keyViews {
            for touch in touches {
                let currentLocation = touch.locationInView(keyContainer)
                let previousLocation = touch.previousLocationInView(keyContainer)
                if CGRectContainsPoint(key.frame, currentLocation) {
                    let kbTouch = KeyboardTouch(pitch: key.pitch,
                        force: self.forceWithTouch(touch),
                        initialLocation: touch.locationInView(key),
                        keySize: key.bounds.size)
                    kbTouches.insert(kbTouch)
                    keyTouchTuples.append((key, kbTouch))
                }
                else if CGRectContainsPoint(key.frame, previousLocation) {
                    removedKeys.append(key)
                }
            }
        }
        return (kbTouches, removedKeys, keyTouchTuples)
    }

    private func updateWithNewTouches(keyTouches: [(KeyView, KeyboardTouch)]) {
        for (key, touch) in keyTouches {
            key.force = touch.force
        }
    }

    private func updateWithChangedTouches(keyTouches: [(KeyView, KeyboardTouch)],
        removedKeys: [KeyView])
    {
        for (key, touch) in keyTouches {
            key.force = touch.force
        }
        for key in removedKeys {
            key.force = 0
        }
    }

    private func updateWithRemovedTouches(keyTouches: [(KeyView, KeyboardTouch)]) {
        for (key, _) in keyTouches {
            key.force = 0
        }
    }

    public override func touchesBegan(touches: Set<UITouch>,
        withEvent event: UIEvent?)
    {
        let (kbTouches, _, keyTouchTuples) = parsedTouches(touches)
        viewModel.registerNewTouches(kbTouches)
        updateWithNewTouches(keyTouchTuples)
    }

    public override func touchesMoved(touches: Set<UITouch>,
        withEvent event: UIEvent?)
    {
        let (keyTouches, removedKeys, keyTouchTuples) = parsedTouches(touches)
        viewModel.registerChangedTouches(keyTouches, removedKeys: removedKeys)
        updateWithChangedTouches(keyTouchTuples, removedKeys: removedKeys)
    }

    public override func touchesCancelled(touches: Set<UITouch>?,
        withEvent event: UIEvent?)
    {
        guard let touches = touches else { return }
        let (keyTouches, _, keyTouchTuples) = parsedTouches(touches)
        viewModel.registerRemovedTouches(keyTouches)
        updateWithRemovedTouches(keyTouchTuples)
    }

    public override func touchesEnded(touches: Set<UITouch>,
        withEvent event: UIEvent?)
    {
        let (keyTouches, _, keyTouchTuples) = parsedTouches(touches)
        viewModel.registerRemovedTouches(keyTouches)
        updateWithRemovedTouches(keyTouchTuples)
    }

    // MARK: UIScrollViewDelegate
    public func scrollViewDidScroll(scrollView: UIScrollView) {
        keyContainer.contentOffset = scrollView.contentOffset
    }

}
