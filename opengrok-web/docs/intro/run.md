# OpenGrok Web 运行步骤

> **两套命令**：Bash (Linux/macOS) 用 `./mvnw`，PowerShell (Windows) 用 `.\mvnw.cmd`。PowerShell 下把所有 `-Dxxx=yyy` 用双引号包起来，避免 `.xml` 等带点的值被参数解析器截断。

---

## 两套环境约定

| 端口       | 服务器                         | 作用            | 当前在跑什么                                                                        |
|----------|-----------------------------|---------------|-------------------------------------------------------------------------------|
| **8080** | **Tomcat**                  | **正式环境**      | 旧 `menu.jspf`（`webapps/source/`），suggester 数据齐全，验证推荐输入 UI 的形态参照               |
| **8081** | **Jetty** (`mvn jetty:run`) | **开发 / 测试环境** | 重构后的 `index.jsp`（挂在 `target/source.war`）；**所有本次重构 #1 / #1a–#1u 只在 8081 验收生效** |

8080 不部署本次重构产物，不要在 8080 上做 UI 验收。

---

## 步骤一：安装父依赖（在项目根目录）

**Bash：**
```bash
./mvnw -N install:install-file -Dfile=pom.xml -DgroupId=org.opengrok -DartifactId=opengrok-top -Dversion=1.14.15 -Dpackaging=pom
```

**PowerShell：**
```powershell
.\mvnw.cmd -N install:install-file "-Dfile=pom.xml" "-DgroupId=org.opengrok" "-DartifactId=opengrok-top" "-Dversion=1.14.15" "-Dpackaging=pom"
```

---

## 步骤二：编译并安装依赖模块（仍在项目根目录）

**Bash：**
```bash
./mvnw -DskipTests -Dmaven.javadoc.skip=true -Dcheckstyle.skip=true -pl opengrok-indexer,plugins,suggester,opengrok-web install
```

**PowerShell：**
```powershell
.\mvnw.cmd -DskipTests "-Dmaven.javadoc.skip=true" "-Dcheckstyle.skip=true" -pl opengrok-indexer,plugins,suggester,opengrok-web install
```

---

## 步骤三：在 `opengrok-web` 子目录构建 `target/source.war`

**Bash：**
```bash
cd opengrok-web
../mvnw -DskipTests clean package -q
```

**PowerShell：**
```powershell
cd opengrok-web
..\mvnw.cmd -DskipTests clean package -q
```

这一步会跑 JSPC（JSP→Servlet 预编译）到 `target/jspc/`，并打成 `target/source.war`。

---

## 步骤四：启动 Jetty 开发服务器（端口 8081）

仍在 `opengrok-web` 目录。

**Bash：**
```bash
../mvnw -DskipTests jetty:run
```

**PowerShell：**
```powershell
..\mvnw.cmd -DskipTests jetty:run
```

启动后访问 **`http://localhost:8081/`** 即可看到重构后的首页。

> ⚠ **修改 JSP 后必须重启 Jetty**：`mvn jetty:run` 用 JSPC 预编译产物，不会自动 watch JSP 改动。每次改 `.jsp` 后 Ctrl+C 终止 → `mvnw jetty:run` 重启 → 浏览器 Ctrl+Shift+R 硬刷。

---

## 步骤五（可选）：发布到正式 Tomcat（端口 8080）

验收通过后，把 `target/source.war` 拷到 Tomcat 部署：

```powershell
Stop-Service Tomcat9
Copy-Item "D:\Programs\apache_tomcat\webapps\source.war" "D:\Programs\apache_tomcat\webapps\source.war.bak" -Force
Copy-Item "D:\AppsData\deploy\opengrok\opengrok-web\target\source.war" "D:\Programs\apache_tomcat\webapps\source.war" -Force
Remove-Item -Recurse -Force "D:\Programs\apache_tomcat\webapps\source"
Start-Service Tomcat9
Start-Sleep -Seconds 8
```

访问 `http://localhost:8080/source/` 验证。

---

## index.jsp 一句话总结

本次重构**只**改 `opengrok-web/src/main/webapp/index.jsp` 这一个 JSP 文件。完整改动记录与回滚方法见 `docs/plan/ui-refactor.md`（#1 → #1u 共 19 条修改条目）。

---

## 通用排查

| 现象                                     | 处理                                                                        |
|----------------------------------------|---------------------------------------------------------------------------|
| 改了 `.jsp` 没生效                          | 重启 Jetty（步骤四） + 浏览器硬刷新 Ctrl+Shift+R                                       |
| Jetty 启动报 `port 8080 in use`           | `Get-Process -Name java`，按 mtime 杀最旧的 PID                                 |
| 改了 `style-*.css` / `default/img/*` 没变化 | DevTools Network 勾"Disable cache"，或硬刷新                                    |
| autocomplete 下拉无内容 / 项目名 baseline 不齐   | 直接看 `docs/plan/ui-refactor.md` 的对应修改条目（按修复时间倒序在 #1u → #1p → #1o → #1n 排查） |
