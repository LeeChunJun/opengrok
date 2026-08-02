# 步骤一：安装父依赖
```bash
./mvnw -N install:install-file -Dfile=pom.xml -Dgroup=org.opengrok -DartifactId=opengrok-top -Dversion=1.14.15 -Dpackage=pom
```

# 步骤二：编译并安装依赖模块
```bash
./mvnw -DskipTests -Dmaven.javadoc.skip=true -Dcheckstyle.skip=true -pl opengrok-indexer, plugins, suggester, opengrok-web install
```

# 步骤三：构建 opengrok-web，生成 .min.css / .min.js
```bash
cd opengrok-web
../mvnw -DskipTests clean package -q
```

# 步骤四：启动 jetty
```bash
../mvnw -DskipTests org.eclipse.jetty.ee10:jetty-ee10-jspc-maven-plugin:12.0.10:run
```