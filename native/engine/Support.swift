// The small pieces of AXe (MIT, github.com/cameroncooke/AXe) that TextToHIDEvents.swift expects.
import Foundation
protocol UserFacingError: Error, CustomStringConvertible { var userFacingDescription: String { get } }
extension UserFacingError { var description: String { userFacingDescription } }
