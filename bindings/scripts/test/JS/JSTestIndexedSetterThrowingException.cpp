/*
    This file is part of the WebKit open source project.
    This file has been generated by generate-bindings.pl. DO NOT MODIFY!

    This library is free software; you can redistribute it and/or
    modify it under the terms of the GNU Library General Public
    License as published by the Free Software Foundation; either
    version 2 of the License, or (at your option) any later version.

    This library is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
    Library General Public License for more details.

    You should have received a copy of the GNU Library General Public License
    along with this library; see the file COPYING.LIB.  If not, write to
    the Free Software Foundation, Inc., 51 Franklin Street, Fifth Floor,
    Boston, MA 02110-1301, USA.
*/

#include "config.h"
#include "JSTestIndexedSetterThrowingException.h"

#include "JSDOMBinding.h"
#include "JSDOMConstructorNotConstructable.h"
#include "JSDOMConvertStrings.h"
#include "JSDOMExceptionHandling.h"
#include "JSDOMWrapperCache.h"
#include "URL.h"
#include <JavaScriptCore/FunctionPrototype.h>
#include <JavaScriptCore/JSCInlines.h>
#include <JavaScriptCore/PropertyNameArray.h>
#include <wtf/GetPtr.h>
#include <wtf/PointerPreparations.h>


namespace WebCore {
using namespace JSC;

// Attributes

JSC::EncodedJSValue jsTestIndexedSetterThrowingExceptionConstructor(JSC::ExecState*, JSC::EncodedJSValue, JSC::PropertyName);
bool setJSTestIndexedSetterThrowingExceptionConstructor(JSC::ExecState*, JSC::EncodedJSValue, JSC::EncodedJSValue);

class JSTestIndexedSetterThrowingExceptionPrototype : public JSC::JSNonFinalObject {
public:
    using Base = JSC::JSNonFinalObject;
    static JSTestIndexedSetterThrowingExceptionPrototype* create(JSC::VM& vm, JSDOMGlobalObject* globalObject, JSC::Structure* structure)
    {
        JSTestIndexedSetterThrowingExceptionPrototype* ptr = new (NotNull, JSC::allocateCell<JSTestIndexedSetterThrowingExceptionPrototype>(vm.heap)) JSTestIndexedSetterThrowingExceptionPrototype(vm, globalObject, structure);
        ptr->finishCreation(vm);
        return ptr;
    }

    DECLARE_INFO;
    static JSC::Structure* createStructure(JSC::VM& vm, JSC::JSGlobalObject* globalObject, JSC::JSValue prototype)
    {
        return JSC::Structure::create(vm, globalObject, prototype, JSC::TypeInfo(JSC::ObjectType, StructureFlags), info());
    }

private:
    JSTestIndexedSetterThrowingExceptionPrototype(JSC::VM& vm, JSC::JSGlobalObject*, JSC::Structure* structure)
        : JSC::JSNonFinalObject(vm, structure)
    {
    }

    void finishCreation(JSC::VM&);
};

using JSTestIndexedSetterThrowingExceptionConstructor = JSDOMConstructorNotConstructable<JSTestIndexedSetterThrowingException>;

template<> JSValue JSTestIndexedSetterThrowingExceptionConstructor::prototypeForStructure(JSC::VM& vm, const JSDOMGlobalObject& globalObject)
{
    UNUSED_PARAM(vm);
    return globalObject.functionPrototype();
}

template<> void JSTestIndexedSetterThrowingExceptionConstructor::initializeProperties(VM& vm, JSDOMGlobalObject& globalObject)
{
    putDirect(vm, vm.propertyNames->prototype, JSTestIndexedSetterThrowingException::prototype(vm, globalObject), JSC::PropertyAttribute::DontDelete | JSC::PropertyAttribute::ReadOnly | JSC::PropertyAttribute::DontEnum);
    putDirect(vm, vm.propertyNames->name, jsNontrivialString(&vm, String("TestIndexedSetterThrowingException"_s)), JSC::PropertyAttribute::ReadOnly | JSC::PropertyAttribute::DontEnum);
    putDirect(vm, vm.propertyNames->length, jsNumber(0), JSC::PropertyAttribute::ReadOnly | JSC::PropertyAttribute::DontEnum);
}

template<> const ClassInfo JSTestIndexedSetterThrowingExceptionConstructor::s_info = { "TestIndexedSetterThrowingException", &Base::s_info, nullptr, nullptr, CREATE_METHOD_TABLE(JSTestIndexedSetterThrowingExceptionConstructor) };

/* Hash table for prototype */

static const HashTableValue JSTestIndexedSetterThrowingExceptionPrototypeTableValues[] =
{
    { "constructor", static_cast<unsigned>(JSC::PropertyAttribute::DontEnum), NoIntrinsic, { (intptr_t)static_cast<PropertySlot::GetValueFunc>(jsTestIndexedSetterThrowingExceptionConstructor), (intptr_t) static_cast<PutPropertySlot::PutValueFunc>(setJSTestIndexedSetterThrowingExceptionConstructor) } },
};

const ClassInfo JSTestIndexedSetterThrowingExceptionPrototype::s_info = { "TestIndexedSetterThrowingExceptionPrototype", &Base::s_info, nullptr, nullptr, CREATE_METHOD_TABLE(JSTestIndexedSetterThrowingExceptionPrototype) };

void JSTestIndexedSetterThrowingExceptionPrototype::finishCreation(VM& vm)
{
    Base::finishCreation(vm);
    reifyStaticProperties(vm, JSTestIndexedSetterThrowingException::info(), JSTestIndexedSetterThrowingExceptionPrototypeTableValues, *this);
}

const ClassInfo JSTestIndexedSetterThrowingException::s_info = { "TestIndexedSetterThrowingException", &Base::s_info, nullptr, nullptr, CREATE_METHOD_TABLE(JSTestIndexedSetterThrowingException) };

JSTestIndexedSetterThrowingException::JSTestIndexedSetterThrowingException(Structure* structure, JSDOMGlobalObject& globalObject, Ref<TestIndexedSetterThrowingException>&& impl)
    : JSDOMWrapper<TestIndexedSetterThrowingException>(structure, globalObject, WTFMove(impl))
{
}

void JSTestIndexedSetterThrowingException::finishCreation(VM& vm)
{
    Base::finishCreation(vm);
    ASSERT(inherits(vm, info()));

}

JSObject* JSTestIndexedSetterThrowingException::createPrototype(VM& vm, JSDOMGlobalObject& globalObject)
{
    return JSTestIndexedSetterThrowingExceptionPrototype::create(vm, &globalObject, JSTestIndexedSetterThrowingExceptionPrototype::createStructure(vm, &globalObject, globalObject.objectPrototype()));
}

JSObject* JSTestIndexedSetterThrowingException::prototype(VM& vm, JSDOMGlobalObject& globalObject)
{
    return getDOMPrototype<JSTestIndexedSetterThrowingException>(vm, globalObject);
}

JSValue JSTestIndexedSetterThrowingException::getConstructor(VM& vm, const JSGlobalObject* globalObject)
{
    return getDOMConstructor<JSTestIndexedSetterThrowingExceptionConstructor>(vm, *jsCast<const JSDOMGlobalObject*>(globalObject));
}

void JSTestIndexedSetterThrowingException::destroy(JSC::JSCell* cell)
{
    JSTestIndexedSetterThrowingException* thisObject = static_cast<JSTestIndexedSetterThrowingException*>(cell);
    thisObject->JSTestIndexedSetterThrowingException::~JSTestIndexedSetterThrowingException();
}

bool JSTestIndexedSetterThrowingException::getOwnPropertySlot(JSObject* object, ExecState* state, PropertyName propertyName, PropertySlot& slot)
{
    auto* thisObject = jsCast<JSTestIndexedSetterThrowingException*>(object);
    ASSERT_GC_OBJECT_INHERITS(thisObject, info());
    if (auto index = parseIndex(propertyName)) {
        if (index.value() < thisObject->wrapped().length()) {
            auto value = toJS<IDLDOMString>(*state, thisObject->wrapped().item(index.value()));
            slot.setValue(thisObject, static_cast<unsigned>(0), value);
            return true;
        }
    }
    return JSObject::getOwnPropertySlot(object, state, propertyName, slot);
}

bool JSTestIndexedSetterThrowingException::getOwnPropertySlotByIndex(JSObject* object, ExecState* state, unsigned index, PropertySlot& slot)
{
    auto* thisObject = jsCast<JSTestIndexedSetterThrowingException*>(object);
    ASSERT_GC_OBJECT_INHERITS(thisObject, info());
    if (LIKELY(index <= MAX_ARRAY_INDEX)) {
        if (index < thisObject->wrapped().length()) {
            auto value = toJS<IDLDOMString>(*state, thisObject->wrapped().item(index));
            slot.setValue(thisObject, static_cast<unsigned>(0), value);
            return true;
        }
    }
    return JSObject::getOwnPropertySlotByIndex(object, state, index, slot);
}

void JSTestIndexedSetterThrowingException::getOwnPropertyNames(JSObject* object, ExecState* state, PropertyNameArray& propertyNames, EnumerationMode mode)
{
    auto* thisObject = jsCast<JSTestIndexedSetterThrowingException*>(object);
    ASSERT_GC_OBJECT_INHERITS(object, info());
    for (unsigned i = 0, count = thisObject->wrapped().length(); i < count; ++i)
        propertyNames.add(Identifier::from(state, i));
    JSObject::getOwnPropertyNames(object, state, propertyNames, mode);
}

bool JSTestIndexedSetterThrowingException::put(JSCell* cell, ExecState* state, PropertyName propertyName, JSValue value, PutPropertySlot& putPropertySlot)
{
    auto* thisObject = jsCast<JSTestIndexedSetterThrowingException*>(cell);
    ASSERT_GC_OBJECT_INHERITS(thisObject, info());

    if (auto index = parseIndex(propertyName)) {
        auto throwScope = DECLARE_THROW_SCOPE(state->vm());
        auto nativeValue = convert<IDLDOMString>(*state, value);
        RETURN_IF_EXCEPTION(throwScope, true);
        propagateException(*state, throwScope, thisObject->wrapped().setItem(index.value(), WTFMove(nativeValue)));
        return true;
    }

    return JSObject::put(thisObject, state, propertyName, value, putPropertySlot);
}

bool JSTestIndexedSetterThrowingException::putByIndex(JSCell* cell, ExecState* state, unsigned index, JSValue value, bool shouldThrow)
{
    auto* thisObject = jsCast<JSTestIndexedSetterThrowingException*>(cell);
    ASSERT_GC_OBJECT_INHERITS(thisObject, info());

    if (LIKELY(index <= MAX_ARRAY_INDEX)) {
        auto throwScope = DECLARE_THROW_SCOPE(state->vm());
        auto nativeValue = convert<IDLDOMString>(*state, value);
        RETURN_IF_EXCEPTION(throwScope, true);
        propagateException(*state, throwScope, thisObject->wrapped().setItem(index, WTFMove(nativeValue)));
        return true;
    }

    return JSObject::putByIndex(cell, state, index, value, shouldThrow);
}

bool JSTestIndexedSetterThrowingException::defineOwnProperty(JSObject* object, ExecState* state, PropertyName propertyName, const PropertyDescriptor& propertyDescriptor, bool shouldThrow)
{
    auto* thisObject = jsCast<JSTestIndexedSetterThrowingException*>(object);
    ASSERT_GC_OBJECT_INHERITS(thisObject, info());

    if (auto index = parseIndex(propertyName)) {
        if (!propertyDescriptor.isDataDescriptor())
            return false;
        auto throwScope = DECLARE_THROW_SCOPE(state->vm());
        auto nativeValue = convert<IDLDOMString>(*state, propertyDescriptor.value());
        RETURN_IF_EXCEPTION(throwScope, true);
        propagateException(*state, throwScope, thisObject->wrapped().setItem(index.value(), WTFMove(nativeValue)));
        return true;
    }

    PropertyDescriptor newPropertyDescriptor = propertyDescriptor;
    newPropertyDescriptor.setConfigurable(true);
    return JSObject::defineOwnProperty(object, state, propertyName, newPropertyDescriptor, shouldThrow);
}

EncodedJSValue jsTestIndexedSetterThrowingExceptionConstructor(ExecState* state, EncodedJSValue thisValue, PropertyName)
{
    VM& vm = state->vm();
    auto throwScope = DECLARE_THROW_SCOPE(vm);
    auto* prototype = jsDynamicCast<JSTestIndexedSetterThrowingExceptionPrototype*>(vm, JSValue::decode(thisValue));
    if (UNLIKELY(!prototype))
        return throwVMTypeError(state, throwScope);
    return JSValue::encode(JSTestIndexedSetterThrowingException::getConstructor(state->vm(), prototype->globalObject()));
}

bool setJSTestIndexedSetterThrowingExceptionConstructor(ExecState* state, EncodedJSValue thisValue, EncodedJSValue encodedValue)
{
    VM& vm = state->vm();
    auto throwScope = DECLARE_THROW_SCOPE(vm);
    auto* prototype = jsDynamicCast<JSTestIndexedSetterThrowingExceptionPrototype*>(vm, JSValue::decode(thisValue));
    if (UNLIKELY(!prototype)) {
        throwVMTypeError(state, throwScope);
        return false;
    }
    // Shadowing a built-in constructor
    return prototype->putDirect(vm, vm.propertyNames->constructor, JSValue::decode(encodedValue));
}

bool JSTestIndexedSetterThrowingExceptionOwner::isReachableFromOpaqueRoots(JSC::Handle<JSC::Unknown> handle, void*, SlotVisitor& visitor)
{
    UNUSED_PARAM(handle);
    UNUSED_PARAM(visitor);
    return false;
}

void JSTestIndexedSetterThrowingExceptionOwner::finalize(JSC::Handle<JSC::Unknown> handle, void* context)
{
    auto* jsTestIndexedSetterThrowingException = static_cast<JSTestIndexedSetterThrowingException*>(handle.slot()->asCell());
    auto& world = *static_cast<DOMWrapperWorld*>(context);
    uncacheWrapper(world, &jsTestIndexedSetterThrowingException->wrapped(), jsTestIndexedSetterThrowingException);
}

#if ENABLE(BINDING_INTEGRITY)
#if PLATFORM(WIN)
#pragma warning(disable: 4483)
extern "C" { extern void (*const __identifier("??_7TestIndexedSetterThrowingException@WebCore@@6B@")[])(); }
#else
extern "C" { extern void* _ZTVN7WebCore34TestIndexedSetterThrowingExceptionE[]; }
#endif
#endif

JSC::JSValue toJSNewlyCreated(JSC::ExecState*, JSDOMGlobalObject* globalObject, Ref<TestIndexedSetterThrowingException>&& impl)
{

#if ENABLE(BINDING_INTEGRITY)
    void* actualVTablePointer = *(reinterpret_cast<void**>(impl.ptr()));
#if PLATFORM(WIN)
    void* expectedVTablePointer = WTF_PREPARE_VTBL_POINTER_FOR_INSPECTION(__identifier("??_7TestIndexedSetterThrowingException@WebCore@@6B@"));
#else
    void* expectedVTablePointer = WTF_PREPARE_VTBL_POINTER_FOR_INSPECTION(&_ZTVN7WebCore34TestIndexedSetterThrowingExceptionE[2]);
#endif

    // If this fails TestIndexedSetterThrowingException does not have a vtable, so you need to add the
    // ImplementationLacksVTable attribute to the interface definition
    static_assert(std::is_polymorphic<TestIndexedSetterThrowingException>::value, "TestIndexedSetterThrowingException is not polymorphic");

    // If you hit this assertion you either have a use after free bug, or
    // TestIndexedSetterThrowingException has subclasses. If TestIndexedSetterThrowingException has subclasses that get passed
    // to toJS() we currently require TestIndexedSetterThrowingException you to opt out of binding hardening
    // by adding the SkipVTableValidation attribute to the interface IDL definition
    RELEASE_ASSERT(actualVTablePointer == expectedVTablePointer);
#endif
    return createWrapper<TestIndexedSetterThrowingException>(globalObject, WTFMove(impl));
}

JSC::JSValue toJS(JSC::ExecState* state, JSDOMGlobalObject* globalObject, TestIndexedSetterThrowingException& impl)
{
    return wrap(state, globalObject, impl);
}

TestIndexedSetterThrowingException* JSTestIndexedSetterThrowingException::toWrapped(JSC::VM& vm, JSC::JSValue value)
{
    if (auto* wrapper = jsDynamicCast<JSTestIndexedSetterThrowingException*>(vm, value))
        return &wrapper->wrapped();
    return nullptr;
}

}
