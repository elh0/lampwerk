import Foundation

/// Measured output and wall draw for each head, from the maker's spec sheet where we could get one.
/// Lux is normalised to 3 m in the beam listed; `LightMath` scales it for distance, output and modifiers.
/// Nothing here is gaffer-checked yet: add an id to `checked` once a gaffer has signed it off.
extension Lamp {
    struct Spec: Hashable, Sendable {
        enum Source: String, Sendable {
            case maker, retailer, estimate

            var title: String {
                switch self {
                case .maker: "Maker spec sheet"
                case .retailer: "Hire house or retailer listing"
                case .estimate: "Approximate"
                }
            }
        }

        /// Lux at 3 m on the beam centre, full output, in the configuration measured.
        let lux3m: Double
        /// Full beam angle of that configuration.
        let beam: Double
        /// Most it pulls from the wall, ballast included.
        let drawW: Double
        let source: Source
        /// What was measured and where it came from, in a line.
        let note: String
        let url: String
    }

    /// Heads a gaffer has checked against what they see on set.
    static let checked: Set<String> = []

    var spec: Spec? { Lamp.specs[id] }
    var isChecked: Bool { Lamp.checked.contains(id) }

    static let specs: [String: Spec] = [
        "s30": Spec(lux3m: 782, beam: 105, drawW: 200, source: .maker, note: "ARRI spec sheet, standard diffusion, 5600 K",
                    url: "https://www.arri.com/resource/blob/31086/f96ceba3698db613978124e3b81eccd7/arri-skypanel-s30-c-data-sheet-de-data.pdf"),
        "s60": Spec(lux3m: 1535, beam: 105, drawW: 400, source: .maker, note: "ARRI spec sheet, standard diffusion, 5600 K",
                    url: "https://www.arri.com/resource/blob/31122/0f77db606e1684a18e4b26d158637cac/arri-skypanel-s60-c-data-sheet-de-data.pdf"),
        "x21": Spec(lux3m: 1839, beam: 121, drawW: 800, source: .retailer, note: "Retailer listing, open face, 5600 K (ARRI publishes the 11° hard setting only)",
                    url: "https://www.arri.com/resource/blob/341262/e55242c6535912778f7f39d38f490c90/arri-skypanel-x-data-sheet-en-data.pdf"),
        "gem": Spec(lux3m: 614, beam: 95, drawW: 200, source: .maker, note: "Litepanels spec, 1x1 Soft, bare, 5600 K",
                    url: "https://www.litepanels.com/en/product/gemini-1x1-soft-rgbww-led-panel-(standard-yoke,-bare-ends)/"),
        "lm4": Spec(lux3m: 834, beam: 120, drawW: 200, source: .maker, note: "LiteGear spec, bare mat, 5600 K",
                    url: "https://www.litegear.com/download/557/litemat-spectrum-2023/47607/litemat-spectrum-4-gen-2-data-sheet.pdf"),
        "a600": Spec(lux3m: 5020, beam: 55, drawW: 720, source: .maker, note: "Aputure photometrics, Hyper Reflector, 5600 K",
                    url: "https://help.aputure.com/en/ls600c-pro/photometrics-technical-specifications"),
        "a1200": Spec(lux3m: 6380, beam: 66, drawW: 1440, source: .maker, note: "Aputure photometrics, bare, 5600 K",
                    url: "https://help.aputure.com/en/ls1200d-pro/photometrics-technical-specifications-ls-1200d-pro"),
        "forza": Spec(lux3m: 8376, beam: 55, drawW: 560, source: .maker, note: "Nanlite spec, Forza 500 II, 55° reflector, 5600 K",
                    url: "http://classic-en.nanlite.com/products/topic/Forza_300_300B_500_500B_II"),
        "vtx": Spec(lux3m: 2340, beam: 110, drawW: 660, source: .maker, note: "Creamsource spec, open face, 5600 K",
                    url: "https://knowledge.creamsource.com/specs-for-the-vortex8"),
        "orb": Spec(lux3m: 2333, beam: 60, drawW: 500, source: .maker, note: "ARRI spec sheet, Open Face 60°, 5600 K",
                    url: "https://www.arri.com/resource/blob/307622/5dcff8f9cced78fd7c5aad7194e1a4d0/arri-orbiter-datenblatt-de-sep2022-data.pdf (2022)"),
        "titan": Spec(lux3m: 87, beam: 135, drawW: 48, source: .maker, note: "Astera datasheet, bare tube, 4000 K (785 lx at 1 m)",
                    url: "https://astera-led.com/wp-content/uploads/FP1_Titan-Tube_Datasheet_V3.pdf"),
        "helios": Spec(lux3m: 44, beam: 135, drawW: 24, source: .maker, note: "Astera datasheet, bare tube, 4000 K (393 lx at 1 m)",
                    url: "https://astera-led.com/products/helios-tube/specs/"),
        "pavo": Spec(lux3m: 84, beam: 160, drawW: 70, source: .maker, note: "Nanlite spec, bare tube, 5600 K. Draw is disputed: 36 W on retailer listings",
                    url: "http://classic-en.nanlite.com/products/topic/PavoTube-II-15X-30X-60X"),
        "b7c": Spec(lux3m: 12, beam: 300, drawW: 12, source: .maker, note: "Aputure photometrics, bare bulb, 5500 K (110 lx at 1 m)",
                    url: "https://help.aputure.com/en/b7c-bulb/photometrics-technical-specifications"),
        "m18": Spec(lux3m: 23556, beam: 40, drawW: 2000, source: .maker, note: "ARRI spec sheet, medium lens 40° (2,120 lx at 10 m). Draw estimated from \"under 13 A at 230 V\"",
                    url: "https://www.arri.com/resource/blob/31486/1a6209e7e85fadca556066f12b551f72/arri-m-series-m18-data-sheet-en-sep2018-data.pdf (2018)"),
        "h12": Spec(lux3m: 27222, beam: 30, drawW: 1300, source: .estimate, note: "Estimate: ARRISUN 12 Plus medium lens scaled from ARRI's spot figure",
                    url: "https://utopiacam.com/wp-content/uploads/2016/06/arrisunbrochure.pdf"),
        "h4": Spec(lux3m: 75667, beam: 30, drawW: 5300, source: .maker, note: "ARRI spec sheet, ARRISUN 40/25 flood lens 42x20° (6,810 lx at 10 m). Draw from ballast VA",
                    url: "https://www.arri.com/resource/blob/162056/b8de5fd5edfbc748001769ce9bcc744e/arri-as-40-data-sheet-en-data.pdf (2011)"),
        "h18": Spec(lux3m: 80670, beam: 50, drawW: 19400, source: .retailer, note: "Retailer listing, ARRI Daylight 18 full flood (1,797 lx at 20 m)",
                    url: "https://www.bhphotovideo.com/c/product/192478-REG/Arri_563205_12K_18KW_HMI.html"),
        "t300": Spec(lux3m: 500, beam: 55, drawW: 300, source: .maker, note: "ARRI spec sheet, 300 Plus full flood, 3200 K",
                    url: "https://www.arri.com/resource/blob/188698/8bc09e82a6d47b2dccd9e052ddf00b7f/arri-fresnel-overview-poster-en-aug22-data.pdf (2022)"),
        "t650": Spec(lux3m: 1194, beam: 54, drawW: 650, source: .maker, note: "ARRI spec sheet, 650 Plus full flood, 3200 K",
                    url: "https://www.arri.com/resource/blob/188698/8bc09e82a6d47b2dccd9e052ddf00b7f/arri-fresnel-overview-poster-en-aug22-data.pdf (2022)"),
        "t1k": Spec(lux3m: 2033, beam: 54, drawW: 1000, source: .retailer, note: "Hire house listing, 1K junior full flood, 3200 K",
                    url: "https://www.panavision.com/lighting/lighting-products/heads/product-detail/iaa04a0-1kw-junior-fresnel-"),
        "t2k": Spec(lux3m: 4560, beam: 57, drawW: 2000, source: .retailer, note: "Retailer listing, 2K full flood, 3200 K (flood scaled from the ST2)",
                    url: "https://www.bhphotovideo.com/c/product/575718-REG/Arri_551201_T2_Location_Fresnel.html"),
        "red": Spec(lux3m: 933, beam: 87, drawW: 800, source: .retailer, note: "Retailer listing, Redhead 800 full flood, 3200 K (2,100 lx at 2 m)",
                    url: "https://www.bhphotovideo.com/c/product/1145959-REG/ltm_pk_red650_redhead_650_800w_pak_kit.html"),
        "china": Spec(lux3m: 18, beam: 300, drawW: 150, source: .estimate, note: "Estimate: 24 in lantern on a 150 W household bulb",
                    url: ""),
    ]
}
