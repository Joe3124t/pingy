import Foundation

struct MultipartFormData {
    private let crlf = "\r\n"
    let boundary: String
    private(set) var data = Data()

    init(boundary: String = "Boundary-\(UUID().uuidString)") {
        self.boundary = boundary
    }

    mutating func appendField(name: String, value: String) {
        let part = """
        --\(boundary)\(crlf)\
        Content-Disposition: form-data; name="\(name)"\(crlf)\
        \(crlf)\
        \(value)\(crlf)
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
        --\(boundary)\(crlf)\
        Content-Disposition: form-data; name="\(fieldName)"; filename="\(fileName)"\(crlf)\
        Content-Type: \(mimeType)\(crlf)\
        \(crlf)
        """
        data.append(header.data(using: .utf8) ?? Data())
        data.append(fileData)
        data.append(crlf.data(using: .utf8) ?? Data())
    }

    mutating func finalize() {
        data.append("--\(boundary)--\(crlf)".data(using: .utf8) ?? Data())
    }
}
