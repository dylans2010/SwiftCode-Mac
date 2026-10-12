# __PROJECT_NAME__

SwiftCode standalone TypeScript project (spec §14.1). User-owned code using
the ordinary Node.js workflow.

__PROJECT_DESCRIPTION__

## Develop

```sh
npm install     # install dev dependencies (typescript, @types/node)
npm run build   # compile src/ -> dist/
npm run typecheck
npm test        # run tests (build first)
node dist/index.js
```

TypeScript `7.0.2` and `@types/node` `26.6.5` are pinned in `package.json`.
