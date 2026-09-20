// @ts-ignore
import * as Path from "node:path"
import { Project, SyntaxKind, Node } from "ts-morph"

// @ts-ignore
const projectRoot = Path.join(import.meta.dirname, "..")

const project = new Project()

const source = project.addSourceFileAtPathIfExists(Path.join(projectRoot, "src/internal/supabase-database.ts"))

if (!source) {
  throw new Error(`Could not find ${source}`)
}

const rowProps = source
  .getDescendantsOfKind(SyntaxKind.PropertySignature)
  .filter((prop) => ["Row", "Insert", "Update"].includes(prop.getName()))

for (const rowProp of rowProps) {
  const typeNode = rowProp.getTypeNode()

  if (!typeNode || !Node.isTypeLiteral(typeNode)) continue

  for (const member of typeNode.getMembers()) {
    if (Node.isPropertySignature(member)) {
      member.setIsReadonly(true)
    }
  }
}

source.saveSync()
