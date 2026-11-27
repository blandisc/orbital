import Foundation
import ObjectiveC

/// Los textos de la Mac dicen «Mac» y «haz clic» (26 nov 2026). El catálogo (`Localizable.xcstrings`) ya trae casi 300 textos
/// con su versión para la Mac («Como la Mac», «Haz clic en uno…»), pero una app del iPad que corre en la Mac recibe la versión
/// del iPad: Ajustes › Apariencia decía «Como el iPad» y Complementos «Toca uno». Aquí, solo en la Mac, `Bundle.main` busca
/// primero la versión «mac» de cada texto; si no tiene, sigue como siempre. En el iPhone y el iPad no se instala.
///
/// SwiftUI no pide sus textos por `localizedString(forKey:value:table:)` sino por las variantes con idioma (y la de texto con
/// formato, para el Markdown de `Text`): se cubren todas las que reciben llave, valor y tabla. Ningún texto «mac» lleva
/// Markdown, así que el texto con formato sale liso sin perder nada.
///
/// Costo: una tabla de ~300 textos que se arma una vez, la primera vez que se pide un texto (unos milisegundos), y una
/// búsqueda en un diccionario por texto después. `DeviceWordsOnMacTests.testTheMacReadsItsOwnVariant` lo cuida.
enum MacStrings {
    static func install() {
        guard ProcessInfo.onMac, !installed else { return }
        installed = true
        for name in ["localizedStringForKey:value:table:localization:", "localizedStringForKey:value:table:localizations:",
                     "_localizedStringForKey:value:table:localizations:"] { hook(name, attributed: false) }
        hook("localizedAttributedStringForKey:value:table:localization:", attributed: true)
        hookThreeArguments("localizedAttributedStringForKey:value:table:", attributed: true)
        object_setClass(Bundle.main, MacVariantBundle.self)
    }

    nonisolated(unsafe) private static var installed = false

    /// La versión «mac» de `key`, si la tabla es la de siempre.
    static func mac(_ key: NSString, table: NSString?) -> String? {
        guard table == nil || table == "Localizable" else { return nil }
        return MacVariantBundle.table[key as String]
    }

    /// Un método de cuatro argumentos (llave, valor, tabla y el idioma): primero la versión «mac», si no la de siempre.
    private static func hook(_ name: String, attributed: Bool) {
        let selector = NSSelectorFromString(name)
        guard let method = class_getInstanceMethod(Bundle.self, selector) else { return }
        typealias Original = @convention(c) (AnyObject, Selector, NSString, NSString?, NSString?, AnyObject?) -> AnyObject
        let original = unsafeBitCast(method_getImplementation(method), to: Original.self)
        let block: @convention(block) (AnyObject, NSString, NSString?, NSString?, AnyObject?) -> AnyObject = { bundle, key, value, table, language in
            if let mac = mac(key, table: table) { return attributed ? NSAttributedString(string: mac) : mac as NSString }
            return original(bundle, selector, key, value, table, language)
        }
        class_addMethod(MacVariantBundle.self, selector, imp_implementationWithBlock(block), method_getTypeEncoding(method))
    }

    private static func hookThreeArguments(_ name: String, attributed: Bool) {
        let selector = NSSelectorFromString(name)
        guard let method = class_getInstanceMethod(Bundle.self, selector) else { return }
        typealias Original = @convention(c) (AnyObject, Selector, NSString, NSString?, NSString?) -> AnyObject
        let original = unsafeBitCast(method_getImplementation(method), to: Original.self)
        let block: @convention(block) (AnyObject, NSString, NSString?, NSString?) -> AnyObject = { bundle, key, value, table in
            if let mac = mac(key, table: table) { return attributed ? NSAttributedString(string: mac) : mac as NSString }
            return original(bundle, selector, key, value, table)
        }
        class_addMethod(MacVariantBundle.self, selector, imp_implementationWithBlock(block), method_getTypeEncoding(method))
    }

    /// Las versiones «mac» del idioma de la app (el primero de `preferredLocalizations`, que la app fija al arrancar).
    static func macVariants(in bundle: Bundle, localization: String?) -> [String: String] {
        guard let url = bundle.url(forResource: "Localizable", withExtension: "stringsdict", subdirectory: nil, localization: localization),
              let dict = NSDictionary(contentsOf: url) as? [String: Any] else { return [:] }
        var table: [String: String] = [:]
        table.reserveCapacity(dict.count)
        for (key, value) in dict {
            guard let entry = value as? [String: Any], let device = entry["NSStringDeviceSpecificRuleType"] as? [String: String],
                  let mac = device["mac"] else { continue }
            table[key] = mac
        }
        return table
    }
}

/// `Bundle.main` en la Mac: la versión «mac» de un texto antes que la del iPad (los demás métodos los agrega `MacStrings`).
private final class MacVariantBundle: Bundle, @unchecked Sendable {
    static let table: [String: String] = MacStrings.macVariants(in: .main, localization: Bundle.main.preferredLocalizations.first)

    override func localizedString(forKey key: String, value: String?, table tableName: String?) -> String {
        if let mac = MacStrings.mac(key as NSString, table: tableName as NSString?) { return mac }
        return super.localizedString(forKey: key, value: value, table: tableName)
    }
}
