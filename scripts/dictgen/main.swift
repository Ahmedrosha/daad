// Builds the keyboard's ready-to-map word lists at build time.
//   swiftc -O -o dictgen Keyboard/WordStore.swift Keyboard/TextFold.swift scripts/dictgen/main.swift
//   ./dictgen ar Keyboard/Resources/words_ar.txt Keyboard/Resources/words_eg.txt Keyboard/Resources/dict_ar.bin
//   ./dictgen en Keyboard/Resources/words_en.txt Keyboard/Resources/dict_en.bin
import Foundation

let args = CommandLine.arguments
func url(_ s: String) -> URL { URL(fileURLWithPath: s) }

let builder: WordListBuilder
let out: URL
switch (args.count, args.count > 1 ? args[1] : "") {
case (5, "ar"):
    builder = WordListBuilder.make(main: url(args[2]), egyptian: url(args[3]), arabic: true)
    out = url(args[4])
case (4, "en"):
    builder = WordListBuilder.make(main: url(args[2]), egyptian: nil, arabic: false)
    out = url(args[3])
default:
    FileHandle.standardError.write("usage: dictgen ar <words_ar> <words_eg> <out> | dictgen en <words_en> <out>\n".data(using: .utf8)!)
    exit(2)
}
guard builder.count > 1000 else {
    FileHandle.standardError.write("only \(builder.count) words read, not writing \(out.path)\n".data(using: .utf8)!)
    exit(1)
}
let data = builder.serialize()
try data.write(to: out)
guard let check = WordList(data: data), check.count == builder.count else {
    FileHandle.standardError.write("written file does not read back\n".data(using: .utf8)!)
    exit(1)
}
print("\(out.lastPathComponent): \(builder.count) words, \(data.count / 1024) KB")
