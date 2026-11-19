#include <jni.h>
#include <string>
#include "gvpb.h"

extern "C" {

JNIEXPORT jint JNICALL
Java_com_example_uuremote_Gvpb nativeMessageCount(JNIEnv*, jclass) {
    return gvpb_schema_message_count();
}

JNIEXPORT jstring JNICALL
Java_com_example_uuremote_Gvpb nativeSchemaName(JNIEnv* env, jclass, jstring jmsg, jint field) {
    const char* msg = env->GetStringUTFChars(jmsg, nullptr);
    const char* name = gvpb_schema_name(msg, field);
    jstring result = name ? env->NewStringUTF(name) : nullptr;
    env->ReleaseStringUTFChars(jmsg, msg);
    return result;
}

JNIEXPORT jint JNICALL
Java_com_example_uuremote_Gvpb nativeFieldNumber(JNIEnv* env, jclass, jstring jmsg, jstring jname) {
    const char* msg = env->GetStringUTFChars(jmsg, nullptr);
    const char* name = env->GetStringUTFChars(jname, nullptr);
    int n = gvpb_schema_number(msg, name);
    env->ReleaseStringUTFChars(jmsg, msg);
    env->ReleaseStringUTFChars(jname, name);
    return n;
}

// 用 core 的 protobuf 编码器把 (field,value) 编成一段消息（用于 InputEvent 构造）
JNIEXPORT jbyteArray JNICALL
Java_com_example_uuremote_Gvpb nativeEncodeVarint(JNIEnv* env, jclass, jint field, jlong value) {
    gvpb_msg* m = gvpb_new();
    gvpb_set_varint(m, field, (uint64_t)value);
    uint8_t buf[64];
    size_t n = gvpb_encode(m, buf, sizeof(buf));
    gvpb_free(m);
    jbyteArray arr = env->NewByteArray((jsize)n);
    env->SetByteArrayRegion(arr, 0, (jsize)n, (const jbyte*)buf);
    return arr;
}

JNIEXPORT jbyteArray JNICALL
Java_com_example_uuremote_Gvpb nativeEncodeString(JNIEnv* env, jclass, jint field, jstring jvalue) {
    const char* value = env->GetStringUTFChars(jvalue, nullptr);
    gvpb_msg* m = gvpb_new();
    gvpb_set_string(m, field, value);
    uint8_t buf[4096];
    size_t n = gvpb_encode(m, buf, sizeof(buf));
    gvpb_free(m);
    env->ReleaseStringUTFChars(jvalue, value);
    jbyteArray arr = env->NewByteArray((jsize)n);
    env->SetByteArrayRegion(arr, 0, (jsize)n, (const jbyte*)buf);
    return arr;
}

} // extern "C"
