//
//  QuickDrawErrors.swift
//  QuickDrawViewer
//
//  Created by Matthias Wiesmann on 02.01.2024.
//

import Foundation

enum QuickDrawError: Error {
  case quickDrawIoError (message: String);
  case unknownOpcodeError (opcode: UInt16);
  case unknownQuickDrawVersionError (version: Int);
  case corruptColorTableError (message: String);
  case missingColorTableError;
  case invalidStr32(length: Int);
  case invalidClutError(clut: QDColorTable);
  case clutTooBigError(clut: QDColorTable);
  case corruptPackbitLine(row: Int, expectedLength : Data.Index, actualLength: Data.Index);
  case corruptRegion(boundingBox: QDRect);
  case renderingError (message: String);
  case wrongComponentNumber(componentNumber : Int);
  case unsupportedVerb(verb: QDVerb);
  case unsupportedQD1Color(colorCode: UInt32);
  case corruptPayload(message: String);
  case invalidFract(message: String);
  case invalidPhotoShopDepth(depth: Int);
  case invalidCommentPayload(payload: CommentPayload);
  case invalidReservedSize(reservedType: ReservedOpType);
  case invalidPackType(packtype: UInt16);
  case corruptRegionLine(line: Int);
  case missingDestinationRect(message: String);
  case unsupportedBlend(fg: QDColor, bg: QDColor);
  case cannotBlend(message: String)
  case cannotConvertToRGB(color: QDColor);
}
