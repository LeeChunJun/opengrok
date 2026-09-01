import type { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import {
  z,
  opengrok,
  textResult,
  errorResult,
  registerReadTool,
  registerWriteTool,
} from "./_helpers.js";

/**
 * 对应接口：/projects* （项目及子资源的完整 CRUD）
 */
export function registerProjectTools(server: McpServer) {
  // ---- 只读 ----

  registerReadTool(
    server,
    "list_projects",
    "列出所有 OpenGrok 项目。",
    {},
    async () => {
      try {
        return textResult(await opengrok.get("/projects"));
      } catch (err) {
        return errorResult(err);
      }
    },
  );

  registerReadTool(
    server,
    "list_indexed_projects",
    "列出索引状态为「已建立索引」的项目。",
    {},
    async () => {
      try {
        return textResult(await opengrok.get("/projects/indexed"));
      } catch (err) {
        return errorResult(err);
      }
    },
  );

  registerReadTool(
    server,
    "get_project_property",
    "读取项目的某一个配置属性。",
    {
      project: z.string(),
      field: z.string().describe("属性字段名。"),
    },
    async ({ project, field }) => {
      try {
        return textResult(
          await opengrok.get(
            `/projects/${encodeURIComponent(project)}/property/${encodeURIComponent(field)}`,
          ),
        );
      } catch (err) {
        return errorResult(err);
      }
    },
  );

  registerReadTool(
    server,
    "get_project_index_files",
    "列出项目对应的索引数据文件清单。",
    { project: z.string() },
    async ({ project }) => {
      try {
        return textResult(
          await opengrok.get(`/projects/${encodeURIComponent(project)}/files`),
        );
      } catch (err) {
        return errorResult(err);
      }
    },
  );

  registerReadTool(
    server,
    "get_project_repositories",
    "列出项目关联的仓库。",
    { project: z.string() },
    async ({ project }) => {
      try {
        return textResult(
          await opengrok.get(
            `/projects/${encodeURIComponent(project)}/repositories`,
          ),
        );
      } catch (err) {
        return errorResult(err);
      }
    },
  );

  registerReadTool(
    server,
    "get_project_repository_type",
    "查询项目底层仓库的类型（Git/SVN/Mercurial 等）。",
    { project: z.string() },
    async ({ project }) => {
      try {
        return textResult(
          await opengrok.get(
            `/projects/${encodeURIComponent(project)}/repositories/type`,
          ),
        );
      } catch (err) {
        return errorResult(err);
      }
    },
  );

  // ---- 写（受开关控制）----

  registerWriteTool(
    server,
    "add_project",
    "注册一个新的 OpenGrok 项目。请求体为纯文本项目名。",
    { name: z.string().describe("纯文本项目名（请求体）。") },
    async ({ name }) => {
      try {
        return textResult(await opengrok.post("/projects", name));
      } catch (err) {
        return errorResult(err);
      }
    },
  );

  registerWriteTool(
    server,
    "delete_project",
    "永久删除一个项目及其索引，不可恢复。",
    { project: z.string() },
    async ({ project }) => {
      try {
        return textResult(
          await opengrok.delete(`/projects/${encodeURIComponent(project)}`),
        );
      } catch (err) {
        return errorResult(err);
      }
    },
  );

  registerWriteTool(
    server,
    "set_project_property",
    "设置项目的某一个配置属性。",
    {
      project: z.string(),
      field: z.string(),
      value: z.string().describe("属性新值（请求体）。"),
    },
    async ({ project, field, value }) => {
      try {
        return textResult(
          await opengrok.put(
            `/projects/${encodeURIComponent(project)}/property/${encodeURIComponent(field)}`,
            value,
          ),
        );
      } catch (err) {
        return errorResult(err);
      }
    },
  );

  registerWriteTool(
    server,
    "delete_project_data",
    "删除一个项目的全部索引数据（保留项目注册）。",
    { project: z.string() },
    async ({ project }) => {
      try {
        return textResult(
          await opengrok.delete(`/projects/${encodeURIComponent(project)}/data`),
        );
      } catch (err) {
        return errorResult(err);
      }
    },
  );

  registerWriteTool(
    server,
    "delete_project_annotation_cache",
    "清空项目的注解（blame）缓存。",
    { project: z.string() },
    async ({ project }) => {
      try {
        return textResult(
          await opengrok.delete(
            `/projects/${encodeURIComponent(project)}/annotationcache`,
          ),
        );
      } catch (err) {
        return errorResult(err);
      }
    },
  );

  registerWriteTool(
    server,
    "delete_project_history_cache",
    "清空项目的 SCM 历史缓存。",
    { project: z.string() },
    async ({ project }) => {
      try {
        return textResult(
          await opengrok.delete(
            `/projects/${encodeURIComponent(project)}/historycache`,
          ),
        );
      } catch (err) {
        return errorResult(err);
      }
    },
  );

  registerWriteTool(
    server,
    "mark_project_indexed",
    "把项目标记为「已重新索引」（重置索引时间戳）。",
    { project: z.string() },
    async ({ project }) => {
      try {
        return textResult(
          await opengrok.put(`/projects/${encodeURIComponent(project)}/indexed`),
        );
      } catch (err) {
        return errorResult(err);
      }
    },
  );
}
