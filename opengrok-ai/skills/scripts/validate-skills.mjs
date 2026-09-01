#!/usr/bin/env node
/**
 * validate-skills.mjs
 *
 * 校验 skills/ 目录下所有 SKILL.md 是否满足：
 *   1. 文件存在
 *   2. 第一行是 `---`（YAML frontmatter 开始）
 *   3. 第三行是 `---`（YAML frontmatter 结束）
 *   4. 含 `name:` 字段
 *   5. 含 `description:` 字段
 *   6. name 与目录名一致
 *
 * 用法：
 *   node skills/scripts/validate-skills.mjs
 *   或加进 package.json: "validate:skills": "node skills/scripts/validate-skills.mjs"
 */

import { readFileSync, readdirSync, statSync } from "node:fs";
import { join, dirname, basename } from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = dirname(fileURLToPath(import.meta.url));
const SKILLS_DIR = join(__dirname, "..");

let failed = 0;
let passed = 0;

function fail(skill, msg) {
  console.error(`  ✗ ${skill}: ${msg}`);
  failed++;
}

function ok(skill, msg) {
  console.log(`  ✓ ${skill}: ${msg}`);
  passed++;
}

function parseFrontmatter(content) {
  // 简单 YAML frontmatter 解析，仅取 name / description 字符串字段。
  if (!content.startsWith("---\n")) return null;
  const end = content.indexOf("\n---\n", 4);
  if (end === -1) return null;
  const block = content.slice(4, end);
  const fields = {};
  for (const line of block.split("\n")) {
    const m = line.match(/^([a-zA-Z_][\w-]*)\s*:\s*(.*)$/);
    if (m) fields[m[1]] = m[2].trim();
  }
  return fields;
}

function validateSkill(skillDir) {
  const name = basename(skillDir);
  const mdPath = join(skillDir, "SKILL.md");

  let stat;
  try {
    stat = statSync(mdPath);
  } catch {
    fail(name, "SKILL.md 不存在");
    return;
  }
  if (!stat.isFile()) {
    fail(name, "SKILL.md 不是文件");
    return;
  }

  const content = readFileSync(mdPath, "utf8");
  const fm = parseFrontmatter(content);

  if (!fm) {
    fail(name, "缺少合法 YAML frontmatter（首行 --- 且第三个 --- 收尾）");
    return;
  }

  if (!fm.name) {
    fail(name, "frontmatter 缺少 name 字段");
    return;
  }

  if (!fm.description) {
    fail(name, "frontmatter 缺少 description 字段");
    return;
  }

  if (fm.name !== name) {
    fail(name, `name="${fm.name}" 与目录名 "${name}" 不一致`);
    return;
  }

  if (fm.description.length < 10) {
    fail(name, "description 太短（建议至少 50 字便于 LLM 加载判断）");
    return;
  }

  ok(name, `OK（description 长度 ${fm.description.length} 字符）`);
}

// 主流程
console.log(`校验 ${SKILLS_DIR} 下的所有 skill...\n`);

const entries = readdirSync(SKILLS_DIR, { withFileTypes: true });
const skillDirs = entries.filter(
  (e) => e.isDirectory() && e.name !== "scripts" && e.name !== "node_modules",
);

if (skillDirs.length === 0) {
  console.error("没找到任何 skill 目录！");
  process.exit(1);
}

for (const dirent of skillDirs) {
  validateSkill(join(SKILLS_DIR, dirent.name));
}

console.log(`\n合计：通过 ${passed}，失败 ${failed}，共 ${skillDirs.length} 个 skill`);
process.exit(failed === 0 ? 0 : 1);
