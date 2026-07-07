import SwiftUI

struct ASCIIArtGeneratorView: View {
    @State private var input = "SwiftCode"
    @State private var output = ""

    var body: some View {
        VStack(spacing: 20) {
            TextField("Enter text", text: $input)
                .textFieldStyle(.roundedBorder)
                .padding()

            Button("Generate ASCII Art") { generate() }
                .buttonStyle(.borderedProminent)

            ScrollView {
                Text(output)
                    .font(.system(.body, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .background(Color.black)
                    .foregroundColor(.green)
            }
            .padding()

            Spacer()
        }
        .navigationTitle("ASCII Art Generator")
    }

    func generate() {
        // A real ASCII art generator would use FIGlet or similar.
        // This is a simplified "blocky" representation.
        output = input.uppercased().map { char -> String in
            switch char {
            case "S": return " #### \n#     \n ###  \n    # \n####  "
            case "W": return "#   # \n#   # \n# # # \n# # # \n # #  "
            case "I": return " ###  \n  #   \n  #   \n  #   \n ###  "
            case "F": return "####  \n#     \n###   \n#     \n#     "
            case "T": return "##### \n  #   \n  #   \n  #   \n  #   "
            case "C": return " #### \n#     \n#     \n#     \n #### "
            case "O": return " #### \n#    #\n#    #\n#    #\n #### "
            case "D": return "###   \n#  #  \n#   # \n#  #  \n###   "
            case "E": return "##### \n#     \n####  \n#     \n##### "
            default: return "  ?   \n"
            }
        }.joined(separator: "\n\n")
    }
}
