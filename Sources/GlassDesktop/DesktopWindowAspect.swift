//
//  DesktopWindowAspect.swift
//  Glass Power Tools — GlassDesktop
//
//  W38 (owner, 2026-10-11, on the Vision Pro with a Mac's two displays each in a window of its own):
//  "we need a way to lock the dimensions to the actual screen ratio". A desktop window resizes only
//  in the shape of the remote display it shows, so the picture fills it without bars. How each
//  platform holds a window to a shape is `GlassWindowAspectLock` (GlassShell), which terminals use
//  too under Scale (D75); what a desktop window has around its picture is here.
//
//  **Which shape.** The picture the window shows (`DesktopSessionModel.pictureAspect`): its display,
//  or the whole desktop. Updated when the display shown, the host's layout, Keep Display Proportions
//  or Match Window Size changes. While Match Window Size makes the remote desktop take the window's
//  size — RDP, or a VNC server that resizes — the window is left free: the desktop follows the window,
//  so there are no bars to avoid, and holding the window to the desktop's shape would chase its own
//  tail. A Mac never resizes its displays to a window, so a Mac's windows are always held.
//

import CoreGraphics
import GlassConnectionUI

/// What a desktop window has around its picture.
enum DesktopWindowAspect {
    /// What a Vision Pro desktop window has around its picture: the remote screen sits
    /// `spatialNestedCanvasInset` (34 points) inside the window's edge on every side (W28), so the
    /// window is 68 points wider and taller than its picture.
    static var spatialChrome: CGSize {
        CGSize(width: GlassWindowShape.spatialNestedCanvasInset * 2, height: GlassWindowShape.spatialNestedCanvasInset * 2)
    }

    /// The smallest a Vision Pro desktop window is (`DesktopSessionView`'s frame).
    static let spatialMinimum = CGSize(width: 800, height: 440)
}
