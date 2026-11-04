#pragma once

// Engine type registry, loaded at runtime from the engine description (.iexd) of the running build.
// One description per platform/build: offsets differ between MSVC (Windows) and Itanium (Linux) layouts.
#include <cstdint>
#include <memory>
#include <string>
#include <unordered_map>
#include <vector>

namespace iex {

enum class Kind {
    I8, U8, I16, U16, I32, U32, I64, U64, F32, F64, Bool,
    ResRef,   // 8 inline chars
    CString,  // pointer to a NUL-terminated buffer
    CharPtr,  // char*
    Chars,    // inline char[count]
    Struct,   // embedded object of `type`
    Ptr,      // pointer to object of `type` (type == nullptr: raw address)
    List,     // embedded CTypedPtrList<CPtrList, type*>
    Array,    // inline array: `count` elements of `element`
};

struct TypeDesc;

struct FieldKind {
    Kind kind = Kind::I32;
    const TypeDesc* type = nullptr;  // Struct, Ptr, List
    std::uint32_t count = 0;         // Chars, Array; List without type: 1 = integer data, 0 = raw pointers
    const FieldKind* element = nullptr;  // Array

    std::uint32_t Size() const;
};

struct FieldDesc {
    std::string name;
    std::uint32_t offset = 0;
    const FieldKind* kind = nullptr;
};

struct TypeDesc {
    std::string name;
    std::uint32_t size = 0;
    std::vector<std::pair<const TypeDesc*, std::uint32_t>> bases;  // base type, offset
    const TypeDesc* element = nullptr;  // list classes (CGameEffectList...): type of the node data
    std::unordered_map<std::string, FieldDesc> fields;

    // Looks the field up in this type, then in its bases. `offset` receives the offset from this type's start.
    const FieldDesc* Find(const std::string& field, std::uint32_t& offset) const;
};

// A `call rel32` instruction of the engine that a hook can redirect.
struct CallSite {
    std::uint32_t rva;
    std::string target;  // mangled name of the called function
};

// An engine member function bound as a Lua method of a class table (`method` record): called with the object
// as `this`, then the Lua arguments marshalled by `args` kinds; the integer result is converted by `ret`.
struct MethodDesc {
    std::string className;
    std::string luaName;
    bool isVirtual = false;     // true: `target` is a vtable byte offset; false: image-relative address
    std::uint32_t target = 0;
    std::string ret;            // void, bool, i8..u32, i64, ptr, obj:<Type>
    std::vector<std::string> args;  // bool, i8..u32, i64, ptr, point (CPoint by value), pointref (CPoint const&)
};

// Reads the `build` record of an .iexd file: key=value pairs (e.g. platform=win64 timestamp=0x... imagesize=0x...).
std::unordered_map<std::string, std::string> ReadBuildRecord(const std::string& path);

class TypeRegistry {
public:
    // Parses an .iexd file. Returns false (and logs) on error.
    bool Load(const std::string& path);
    const TypeDesc* Get(const std::string& name) const;
    std::size_t Count() const { return types_.size(); }
    template <typename F>
    void ForEachType(F&& fn) const
    {
        for (const auto& [name, type] : types_)
            fn(*type);
    }

    // Image-relative address of an engine function or global by mangled name, or 0.
    std::uint32_t Symbol(const std::string& mangled) const;
    // The one function symbol named Class::Method (any parameters), from its Itanium mangling; 0 if none or several.
    std::uint32_t SymbolByQualifiedName(const std::string& qualified) const;
    // Call sites of `target` (mangled name).
    std::vector<std::uint32_t> CallSitesOf(const std::string& target) const;
    // Build-specific constant (`const` record). Returns false if absent.
    bool Const(const std::string& name, std::uint64_t& value) const;
    const std::vector<MethodDesc>& Methods() const { return methods_; }
    // CPtrList::CNode whose `data` points to `element` and whose pNext / pPrev are nodes of the same kind
    // (made on first use from the description's CPtrList::CNode). nullptr without element or node layout.
    const TypeDesc* TypedNode(const TypeDesc* element);

private:
    std::unordered_map<std::string, std::uint64_t> consts_;
    std::unordered_map<std::string, std::uint32_t> symbols_;
    std::vector<CallSite> callSites_;
    std::vector<MethodDesc> methods_;

    TypeDesc* GetOrAdd(const std::string& name);
    const FieldKind* ParseKind(const std::string& text);

    std::unordered_map<std::string, TypeDesc*> types_;
    std::vector<std::unique_ptr<TypeDesc>> typeStore_;
    std::vector<std::unique_ptr<FieldKind>> kindStore_;
};

extern TypeRegistry engineTypes;

} // namespace iex
