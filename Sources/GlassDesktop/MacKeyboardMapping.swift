// Adapted from RDPKit 0.3.1 Examples/RDPClient (MIT). See THIRD-PARTY-NOTICES.md.
#if os(macOS)
import AppKit
import RDPKit

enum MacRDPKeyboardMapping {
    static func shouldSendScancode(for event: NSEvent) -> Bool {
        if alwaysSendsScancode(forKeyCode: event.keyCode) {
            return true
        }
        return event.modifierFlags.intersection([.command, .control, .option]).isEmpty == false
    }

    static func scancode(forKeyCode keyCode: UInt16) -> RDPKeyboardScancode? {
        switch keyCode {
        case 0:
            RDPKeyboardScancode(code: 0x001E)
        case 1:
            RDPKeyboardScancode(code: 0x001F)
        case 2:
            RDPKeyboardScancode(code: 0x0020)
        case 3:
            RDPKeyboardScancode(code: 0x0021)
        case 4:
            RDPKeyboardScancode(code: 0x0023)
        case 5:
            RDPKeyboardScancode(code: 0x0022)
        case 6:
            RDPKeyboardScancode(code: 0x002C)
        case 7:
            RDPKeyboardScancode(code: 0x002D)
        case 8:
            RDPKeyboardScancode(code: 0x002E)
        case 9:
            RDPKeyboardScancode(code: 0x002F)
        case 10:
            RDPKeyboardScancode(code: 0x0056)
        case 11:
            RDPKeyboardScancode(code: 0x0030)
        case 12:
            RDPKeyboardScancode(code: 0x0010)
        case 13:
            RDPKeyboardScancode(code: 0x0011)
        case 14:
            RDPKeyboardScancode(code: 0x0012)
        case 15:
            RDPKeyboardScancode(code: 0x0013)
        case 16:
            RDPKeyboardScancode(code: 0x0015)
        case 17:
            RDPKeyboardScancode(code: 0x0014)
        case 18:
            RDPKeyboardScancode(code: 0x0002)
        case 19:
            RDPKeyboardScancode(code: 0x0003)
        case 20:
            RDPKeyboardScancode(code: 0x0004)
        case 21:
            RDPKeyboardScancode(code: 0x0005)
        case 22:
            RDPKeyboardScancode(code: 0x0007)
        case 23:
            RDPKeyboardScancode(code: 0x0006)
        case 24:
            RDPKeyboardScancode(code: 0x000D)
        case 25:
            RDPKeyboardScancode(code: 0x000A)
        case 26:
            RDPKeyboardScancode(code: 0x0008)
        case 27:
            RDPKeyboardScancode(code: 0x000C)
        case 28:
            RDPKeyboardScancode(code: 0x0009)
        case 29:
            RDPKeyboardScancode(code: 0x000B)
        case 30:
            RDPKeyboardScancode(code: 0x001B)
        case 31:
            RDPKeyboardScancode(code: 0x0018)
        case 32:
            RDPKeyboardScancode(code: 0x0016)
        case 33:
            RDPKeyboardScancode(code: 0x001A)
        case 34:
            RDPKeyboardScancode(code: 0x0017)
        case 35:
            RDPKeyboardScancode(code: 0x0019)
        case 36:
            RDPKeyboardScancode(code: 0x001C)
        case 37:
            RDPKeyboardScancode(code: 0x0026)
        case 38:
            RDPKeyboardScancode(code: 0x0024)
        case 39:
            RDPKeyboardScancode(code: 0x0028)
        case 40:
            RDPKeyboardScancode(code: 0x0025)
        case 41:
            RDPKeyboardScancode(code: 0x0027)
        case 42:
            RDPKeyboardScancode(code: 0x002B)
        case 43:
            RDPKeyboardScancode(code: 0x0033)
        case 44:
            RDPKeyboardScancode(code: 0x0035)
        case 45:
            RDPKeyboardScancode(code: 0x0031)
        case 46:
            RDPKeyboardScancode(code: 0x0032)
        case 47:
            RDPKeyboardScancode(code: 0x0034)
        case 48:
            RDPKeyboardScancode(code: 0x000F)
        case 49:
            RDPKeyboardScancode(code: 0x0039)
        case 50:
            RDPKeyboardScancode(code: 0x0029)
        case 51:
            RDPKeyboardScancode(code: 0x000E)
        case 53:
            RDPKeyboardScancode(code: 0x0001)
        case 65:
            RDPKeyboardScancode(code: 0x0053)
        case 67:
            RDPKeyboardScancode(code: 0x0037)
        case 69:
            RDPKeyboardScancode(code: 0x004E)
        case 71:
            RDPKeyboardScancode(code: 0x0045)
        case 75:
            RDPKeyboardScancode(code: 0x0035, isExtended: true)
        case 76:
            RDPKeyboardScancode(code: 0x001C, isExtended: true)
        case 78:
            RDPKeyboardScancode(code: 0x004A)
        case 81:
            RDPKeyboardScancode(code: 0x000D)
        case 82:
            RDPKeyboardScancode(code: 0x0052)
        case 83:
            RDPKeyboardScancode(code: 0x004F)
        case 84:
            RDPKeyboardScancode(code: 0x0050)
        case 85:
            RDPKeyboardScancode(code: 0x0051)
        case 86:
            RDPKeyboardScancode(code: 0x004B)
        case 87:
            RDPKeyboardScancode(code: 0x004C)
        case 88:
            RDPKeyboardScancode(code: 0x004D)
        case 89:
            RDPKeyboardScancode(code: 0x0047)
        case 91:
            RDPKeyboardScancode(code: 0x0048)
        case 92:
            RDPKeyboardScancode(code: 0x0049)
        case 114:
            RDPKeyboardScancode(code: 0x0052, isExtended: true)
        case 115:
            RDPKeyboardScancode(code: 0x0047, isExtended: true)
        case 116:
            RDPKeyboardScancode(code: 0x0049, isExtended: true)
        case 117:
            RDPKeyboardScancode(code: 0x0053, isExtended: true)
        case 119:
            RDPKeyboardScancode(code: 0x004F, isExtended: true)
        case 121:
            RDPKeyboardScancode(code: 0x0051, isExtended: true)
        case 123:
            RDPKeyboardScancode(code: 0x004B, isExtended: true)
        case 124:
            RDPKeyboardScancode(code: 0x004D, isExtended: true)
        case 125:
            RDPKeyboardScancode(code: 0x0050, isExtended: true)
        case 126:
            RDPKeyboardScancode(code: 0x0048, isExtended: true)
        case 122:
            RDPKeyboardScancode(code: 0x003B)
        case 120:
            RDPKeyboardScancode(code: 0x003C)
        case 99:
            RDPKeyboardScancode(code: 0x003D)
        case 118:
            RDPKeyboardScancode(code: 0x003E)
        case 96:
            RDPKeyboardScancode(code: 0x003F)
        case 97:
            RDPKeyboardScancode(code: 0x0040)
        case 98:
            RDPKeyboardScancode(code: 0x0041)
        case 100:
            RDPKeyboardScancode(code: 0x0042)
        case 101:
            RDPKeyboardScancode(code: 0x0043)
        case 109:
            RDPKeyboardScancode(code: 0x0044)
        case 103:
            RDPKeyboardScancode(code: 0x0057)
        case 111:
            RDPKeyboardScancode(code: 0x0058)
        default:
            nil
        }
    }

    static func modifierScancode(forKeyCode keyCode: UInt16) -> RDPKeyboardScancode? {
        switch keyCode {
        case 54:
            RDPKeyboardScancode(code: 0x005C, isExtended: true)
        case 55:
            RDPKeyboardScancode(code: 0x005B, isExtended: true)
        case 56:
            RDPKeyboardScancode(code: 0x002A)
        case 58:
            RDPKeyboardScancode(code: 0x0038)
        case 59:
            RDPKeyboardScancode(code: 0x001D)
        case 60:
            RDPKeyboardScancode(code: 0x0036)
        case 61:
            RDPKeyboardScancode(code: 0x0038, isExtended: true)
        case 62:
            RDPKeyboardScancode(code: 0x001D, isExtended: true)
        default:
            nil
        }
    }

    static func modifierFlag(forKeyCode keyCode: UInt16) -> NSEvent.ModifierFlags? {
        switch keyCode {
        case 54, 55: .command
        case 56, 60: .shift
        case 58, 61: .option
        case 59, 62: .control
        default: nil
        }
    }

    private static func alwaysSendsScancode(forKeyCode keyCode: UInt16) -> Bool {
        switch keyCode {
        case 36, 48, 51, 53,
             65, 67, 69, 71, 75, 76, 78, 81, 82, 83, 84, 85, 86, 87, 88, 89, 91, 92,
             96 ... 101, 103, 109, 111,
             114 ... 117, 119, 121 ... 126:
            true
        default:
            false
        }
    }
}

#endif
