import Foundation

struct CarData {
    static let makes = [
        "Acura",
        "Alfa Romeo",
        "Aston Martin",
        "Audi",
        "Bentley",
        "BMW",
        "Buick",
        "Cadillac",
        "Chevrolet",
        "Chrysler",
        "Citroën",
        "Dodge",
        "Ferrari",
        "Fiat",
        "Fisker",
        "Ford",
        "Genesis",
        "GMC",
        "Honda",
        "Hyundai",
        "Infiniti",
        "Jaguar",
        "Jeep",
        "Kia",
        "Lamborghini",
        "Land Rover",
        "Lexus",
        "Lincoln",
        "Lotus",
        "Lucid",
        "Maserati",
        "Mazda",
        "McLaren",
        "Mercedes-Benz",
        "Mini",
        "Mitsubishi",
        "Nissan",
        "Pagani",
        "Peugeot",
        "Polestar",
        "Porsche",
        "Ram",
        "Renault",
        "Rivian",
        "Rolls-Royce",
        "Saab",
        "Subaru",
        "Suzuki",
        "Tesla",
        "Toyota",
        "Volkswagen",
        "Volvo",
        "Other"
    ]

    static let insuranceProviders = [
        "Allstate",
        "American Family",
        "Amica Mutual",
        "Bristol West",
        "Chubb",
        "Citizens",
        "Country Financial",
        "CSAA (AAA)",
        "Dairyland",
        "Elephant",
        "Erie Insurance",
        "Esurance",
        "Farmers",
        "GEICO",
        "Hagerty",
        "Hanover",
        "Hartford",
        "Kemper",
        "Liberty Mutual",
        "Lemonade",
        "Mapfre",
        "Mercury",
        "MetLife",
        "Nationwide",
        "NJM",
        "Progressive",
        "Root",
        "Safe Auto",
        "Safeco",
        "Shelter",
        "State Farm",
        "Tesla Insurance",
        "The General",
        "Travelers",
        "USAA",
        "Wawanesa",
        "Other"
    ]

    /// Body-style picker options (Add Car, Edit Details). The Garage turns a
    /// car's style into its generic studio render when its exact model has
    /// none (`CarModelRenderer.normalizedStyle`), so a blank one reads as a
    /// sedan — which is why Add Car requires it.
    static let bodyStyles = [
        "Sedan", "Coupe", "Hatchback", "SUV", "Crossover", "Pickup",
        "Van", "Minivan", "Wagon", "Convertible"
    ]

    static let warrantyTypes = [
        "Factory",
        "Powertrain",
        "Bumper-to-Bumper",
        "Certified Pre-Owned (CPO)",
        "Extended / Third-Party",
        "Other"
    ]
}
