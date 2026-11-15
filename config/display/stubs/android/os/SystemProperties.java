package android.os;
public class SystemProperties {
  public static String get(String k, String d) { return d; }
  public static int getInt(String k, int d) { return d; }
  public static boolean getBoolean(String k, boolean d) { return d; }
}
