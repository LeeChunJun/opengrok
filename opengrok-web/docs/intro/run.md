# 运行步骤

> 同时提供 **Bash (Linux/macOS)** 和 **PowerShell (Windows)** 两套命令。
> 在 Windows PowerShell 下需注意两点：
> 1. 用 `mvnw.cmd` 而非 `mvnw`（PowerShell 不能直接执行 shell 脚本）
> 2. 把所有 `-Dxxx=yyy` 参数用双引号包起来，避免 `.xml` 等带点的值被截断

---

## 步骤一：安装父依赖

在项目根目录（包含根 `pom.xml` 的目录）执行。

**Bash (Linux/macOS)：**
```bash
./mvnw -N install:install-file -Dfile=pom.xml -DgroupId=org.opengrok -DartifactId=opengrok-top -Dversion=1.14.15 -Dpackaging=pom
```

**PowerShell (Windows)：**
```powershell
.\mvnw.cmd -N install:install-file "-Dfile=pom.xml" "-DgroupId=org.opengrok" "-DartifactId=opengrok-top" "-Dversion=1.14.15" "-Dpackaging=pom"
```

---

## 步骤二：编译并安装依赖模块

仍在项目根目录执行。

**Bash (Linux/macOS)：**
```bash
./mvnw -DskipTests -Dmaven.javadoc.skip=true -Dcheckstyle.skip=true -pl opengrok-indexer,plugins,suggester,opengrok-web install
```

**PowerShell (Windows)：**
```powershell
.\mvnw.cmd -DskipTests "-Dmaven.javadoc.skip=true" "-Dcheckstyle.skip=true" -pl opengrok-indexer,plugins,suggester,opengrok-web install
```

---

## 步骤三：构建 opengrok-web，生成 .min.css / .min.js

需先进入 `opengrok-web` 子目录。

**Bash (Linux/macOS)：**
```bash
cd opengrok-web
../mvnw -DskipTests clean package -q
```

**PowerShell (Windows)：**
```powershell
cd opengrok-web
..\mvnw.cmd -DskipTests clean package -q
```

---

## 步骤四：启动 Jetty（开发服务器）

需仍在 `opengrok-web` 目录下执行（步骤三已 `cd` 进去）。

**Bash (Linux/macOS)：**
```bash
../mvnw -DskipTests org.eclipse.jetty.ee10:jetty-ee10-maven-plugin:12.0.10:run
```

**PowerShell (Windows)：**
```powershell
..\mvnw.cmd -DskipTests org.eclipse.jetty.ee10:jetty-ee10-maven-plugin:12.0.10:run
```

启动后访问 `http://localhost:8080/source/` 即可。