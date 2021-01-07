set_env_java() {
  ls -l /opt || true
  ls -l /usr/lib/jvm || true

  # Use toolchain java if it exists
  if [ -f /opt/java/jdk8/bin/java ]; then
    export JAVACMD=/opt/java/jdk8/bin/java
  fi
  
  # ppc64le has it in a different place
  if test -z "$JAVACMD" && [ -f /usr/lib/jvm/java-1.8.0/bin/java ]; then
    export JAVACMD=/usr/lib/jvm/java-1.8.0/bin/java
  fi
  
  if true; then
    # newer
    # rhel71-ppc, https://jira.mongodb.org/browse/BUILD-9231
    if test -z "$JAVACMD" &&
      ls /opt/java |grep -q java-1.8.0-openjdk-1.8.0 &&
      test -f /opt/java/java-1.8.0-openjdk-1.8.0*/bin/java;
    then
      path=$(cd /opt/java && ls -d java-1.8.0-openjdk-1.8.0* |head -n 1)
      export JAVACMD=/opt/java/"$path"/bin/java
    fi
  else
    # older
    # rhel71-ppc seems to have an /opt/java/jdk8/bin/java but it doesn't work
    if test -n "$JAVACMD" && ! exec $JAVACMD -version; then
      JAVACMD=
      # we will try the /usr/lib/jvm then
    fi
  fi
  
  if test -n "$JAVACMD"; then
    eval $JAVACMD -version
  else
    which java
    java -version
  fi
}
