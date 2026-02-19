import Foundation

struct MultipartFormData {
    let boundary: String
    private(set) var data = Data()

    init(boundary: String = "Boundary-\(UUID().uuidString)") {
        self.boundary = boundary
    }

    mutating func appendField(name: String, value: String) {
        let part = """
        --\(boundary)\r
        Content-Disposition: form-data; name="\(name)"\r
        \r
        \(value)\r
        """
        data.append(part.data(using: .utf8) ?? Data())
    }

    mutating func appendFile(
        fieldName: String,
        fileName: String,
        mimeType: String,
        fileData: Data
    ) {
        let header = """
        --\(boundary)\r
        Content-Disposition: form-data; name="\(fieldName)"; filename="\(fileName)"\r
        Content-Type: \(mimeType)\r
        \r
        """
        data.append(header.data(using: .utf8) ?? Data())
        data.append(fileData)
        data.append("\r".data(using: .utf8) ?? Data())
    }

    mutating func finalize() {
        data.append("--\(boundary)--\r".data(using: .utf8) ?? Data())
    }
}
