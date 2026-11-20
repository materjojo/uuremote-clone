#!/usr/bin/env python3
"""Regression fixtures for javap parsing; no Java compilation/native execution."""
import unittest
from verify_android_abi import parse_javap


class JavapParsingTests(unittest.TestCase):
    def test_descriptors_are_not_treated_as_method_declarations(self):
        methods, constants = parse_javap("""
public final class com.remote.streamer.Example {
  public static final int UNDEFINED = -1;
    descriptor: I
  public com.remote.streamer.Example(android.content.Context, long, int);
    descriptor: (Landroid/content/Context;JI)V
  private final native int Connect(long, java.nio.ByteBuffer, java.lang.String, java.lang.String);
    descriptor: (JLjava/nio/ByteBuffer;Ljava/lang/String;Ljava/lang/String;)I
  public final void OnReceiveControlData(long, byte[]);
    descriptor: (J[B)V
  public final void OnReceiveControlData(long, java.lang.String);
    descriptor: (JLjava/lang/String;)V
  public final java.lang.String[] getSignalServers();
    descriptor: ()[Ljava/lang/String;
}
""", "com.remote.streamer.Example")
        self.assertEqual(set(methods), {
            ('<init>', '(Landroid/content/Context;JI)V'),
            ('Connect', '(JLjava/nio/ByteBuffer;Ljava/lang/String;Ljava/lang/String;)I'),
            ('OnReceiveControlData', '(J[B)V'),
            ('OnReceiveControlData', '(JLjava/lang/String;)V'),
            ('getSignalServers', '()[Ljava/lang/String;'),
        })
        self.assertIn(' native ', ' ' + methods[('Connect', '(JLjava/nio/ByteBuffer;Ljava/lang/String;Ljava/lang/String;)I')] + ' ')
        self.assertEqual(constants, {'UNDEFINED': -1})

    def test_field_descriptors_and_static_initializers_do_not_create_methods(self):
        methods, _ = parse_javap("""
  private long nativeListener;
    descriptor: J
  static {};
    descriptor: ()V
""", "com.remote.streamer.Example")
        self.assertEqual(methods, {})


if __name__ == '__main__':
    unittest.main()
