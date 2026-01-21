---
name: mega-skill-devops-finops-500
description: Mega skill consolidada de 500+ casos práticos nas verticais DevOps, Infraestrutura, Terraform, Kubernetes, CI/CD e FinOps. Baseada em análise de tendências 2026, AWS Well-Architected Framework e melhores práticas de mercado.
version: 1.0.0
date: 2026-01-19
---

# 🚀 MEGA SKILL: DevOps, Infra, Terraform, Kubernetes, CI/CD e FinOps

**500+ Casos Práticos Organizados por Domínio**

---

## 📋 Índice Rápido

1. [AWS Well-Architected Framework](#1-aws-well-architected-framework)
2. [Terraform & IaC](#2-terraform--iac)
3. [Kubernetes & EKS](#3-kubernetes--eks)
4. [CI/CD Pipelines](#4-cicd-pipelines)
5. [FinOps & Cost Optimization](#5-finops--cost-optimization)
6. [Networking AWS](#6-networking-aws)
7. [Observabilidade](#7-observabilidade)
8. [Secrets Management](#8-secrets-management)
9. [GitOps](#9-gitops)
10. [Security & DevSecOps](#10-security--devsecops)
11. [High Availability & Disaster Recovery](#11-high-availability--disaster-recovery)
12. [Platform Engineering & IDP](#12-platform-engineering--idp)

---

## 1. AWS Well-Architected Framework

### Quando usar
- Arquitetar novas soluções AWS
- Review de arquiteturas existentes
- Justificar decisões técnicas
- Otimizar pilares: segurança, confiabilidade, performance, custo, sustentabilidade

### 6 Pilares

#### 1.1 Excelência Operacional
```bash
# Casos práticos (50+):
1. Automatizar deploy usando IaC (Terraform/CloudFormation)
2. Implementar CI/CD com rollback automático
3. Monitorar métricas operacionais (CloudWatch, Prometheus)
4. Runbooks automatizados para incidentes comuns
5. Game days simulando falhas
6. Tagging consistente para rastreabilidade
7. Change management com aprovações automatizadas
8. Drift detection em IaC
9. Backup/restore automatizado com testes periódicos
10. Documentação como código (docs-as-code)
11. Postmortems blameless após incidentes
12. Alertas actionable (não ruído)
13. Service Level Objectives (SLOs) bem definidos
14. Dashboard consolidado multi-ambiente
15. Automação de patching com janelas de manutenção
```

#### 1.2 Segurança
```bash
# Casos práticos (80+):
16. Princípio do menor privilégio (IAM policies granulares)
17. MFA obrigatório para acesso humano
18. Rotação automática de secrets (AWS Secrets Manager)
19. Criptografia em repouso (EBS, S3, RDS com KMS)
20. Criptografia em trânsito (TLS 1.2+)
21. Security Groups restritivos (whitelist apenas necessário)
22. Network ACLs para defesa em profundidade
23. VPC Flow Logs para auditoria de tráfego
24. CloudTrail habilitado em todas as regiões
25. GuardDuty para detecção de ameaças
26. Secrets nunca em código/variáveis de ambiente
27. Scanning de imagens Docker (Trivy, Snyk)
28. SAST/DAST em pipelines CI/CD
29. Vulnerability scanning com Inspector
30. Compliance automático (Config Rules, SecurityHub)
31. Bastion hosts em vez de SSH direto
32. SSM Session Manager para acesso sem SSH keys
33. IRSA (IAM Roles for Service Accounts) no EKS
34. Pod Security Standards no Kubernetes
35. Network Policies para segmentar pods
36. Admission Controllers (OPA, Kyverno) para policies
37. Secrets criptografados no etcd (EKS encryption)
38. Audit logging habilitado (K8s audit logs)
39. WAF em ALB/CloudFront
40. DDoS protection com Shield
41. Segregação de ambientes (dev/stage/prod em contas separadas)
42. Service Control Policies (SCPs) no Organizations
43. Remediação automática de findings (Lambda + Config)
44. Compliance as Code (Checkov, tfsec, terrascan)
45. Certificate management automatizado (ACM, cert-manager)
```

#### 1.3 Confiabilidade
```bash
# Casos práticos (60+):
46. Multi-AZ deployment obrigatório em produção
47. Auto Scaling Groups com health checks
48. ELB health checks configurados corretamente
49. Circuit breakers em microserviços
50. Retry com exponential backoff
51. Idempotência em APIs e operações
52. Database replication multi-AZ
53. Backup automatizado com retenção definida
54. Disaster Recovery testado periodicamente
55. RTO/RPO documentados e monitorados
56. Chaos engineering (simulação de falhas)
57. Blue/Green deployment para zero downtime
58. Canary deployments com rollback automático
59. Feature flags para release gradual
60. Graceful degradation (falhar sem quebrar tudo)
61. Queue-based decoupling (SQS, Kafka)
62. Dead Letter Queues para mensagens falhas
63. State machine resiliente (Step Functions)
64. Timeout configurado em todas as chamadas
65. Resource limits (CPU/Memory) no Kubernetes
66. PodDisruptionBudgets para high availability
67. Horizontal Pod Autoscaler (HPA)
68. Cluster Autoscaler / Karpenter para nodes
69. Liveness e Readiness probes corretos
70. Rolling updates com maxUnavailable controlado
71. Database connection pooling
72. Cache para reduzir carga (ElastiCache, Redis)
73. CDN para assets estáticos (CloudFront)
74. Rate limiting em APIs (API Gateway)
75. Throttling configurado em serviços críticos
```

#### 1.4 Eficiência de Performance
```bash
# Casos práticos (50+):
76. Right-sizing de instâncias (Compute Optimizer)
77. Uso de instâncias Graviton (ARM, melhor custo/performance)
78. Burst vs baseline (T3/T4g vs M5/M6i)
79. Storage otimizado (GP3 vs GP2, st1 vs sc1)
80. RDS Performance Insights para query tuning
81. ElastiCache para dados frequentes
82. CloudFront para latência global
83. Global Accelerator para tráfego TCP/UDP
84. VPC Endpoints para tráfego privado (sem NAT Gateway)
85. Lambda com Provisioned Concurrency (latência previsível)
86. ECS/EKS com instance types adequados
87. Spot instances para workloads tolerantes a interrupção
88. Container image otimizado (multi-stage build, distroless)
89. Kubernetes resource requests/limits balanceados
90. Node affinity para workloads específicos
91. HPA baseado em métricas custom (não só CPU)
92. Vertical Pod Autoscaler (VPA) para tuning
93. Database indexing adequado
94. Query optimization (EXPLAIN ANALYZE)
95. Read replicas para leitura intensiva
96. Sharding para escala horizontal de DB
97. Async processing (SQS + workers)
98. Streaming vs batch processing (escolha correta)
99. Profiling de aplicações (X-Ray, Jaeger)
100. Compressão de dados (gzip, brotli)
```

#### 1.5 Otimização de Custos
```bash
# Casos práticos (80+):
101. Reserved Instances para workloads estáveis
102. Savings Plans para compute flexível
103. Spot instances com fallback para On-Demand
104. Right-sizing baseado em métricas reais
105. Desligar ambientes dev/test fora do horário comercial
106. S3 Lifecycle policies (Glacier, Deep Archive)
107. S3 Intelligent-Tiering para dados com padrão variável
108. EBS snapshot lifecycle automatizado
109. Remover volumes EBS não utilizados
110. Elastic IPs não associados (cobrança)
111. NAT Gateway vs NAT Instance (custo)
112. VPC Endpoints vs NAT Gateway (custo de transferência)
113. CloudFront cache para reduzir origin requests
114. Lambda memory tuning (mais memória = mais rápido = mais barato)
115. RDS Aurora Serverless v2 para workloads variáveis
116. Fargate Spot para ECS/EKS
117. Graviton instances (até 40% mais barato)
118. Commitment do Compute Optimizer
119. Budgets com alertas e ações automáticas
120. Cost Allocation Tags obrigatórios
121. Chargebacks por equipe/projeto
122. FinOps Dashboard (Cost Explorer customizado)
123. Anomaly Detection habilitado
124. Resource tagging governance com SCPs
125. Multi-Region vs Single Region (trade-off custo)
126. Data transfer costs (inter-AZ, inter-region, internet)
127. CloudWatch Logs retention policy
128. Log filtering antes de ingestar (menos custo)
129. ECS vs EKS vs Lambda (custo por workload)
130. Container density otimizado (bin packing)
131. Karpenter consolidation para reduzir nodes
132. Cluster Autoscaler scale-down policy
133. GP3 vs GP2 (30% mais barato, melhor performance)
134. RDS vs Aurora (custo vs features)
135. Single-AZ vs Multi-AZ (trade-off custo/resiliência)
136. ElastiCache node type otimizado
137. Redshift Reserved Nodes
138. S3 request costs (LIST é caro!)
139. S3 Transfer Acceleration vs CloudFront
140. Direct Connect vs VPN (custo vs latência)
```

#### 1.6 Sustentabilidade
```bash
# Casos práticos (30+):
141. Regiões com energia renovável (us-west-2, ca-central-1)
142. Graviton instances (menor consumo energético)
143. Right-sizing para evitar desperdício
144. Serverless para workloads intermitentes
145. Auto Scaling para desligar recursos ociosos
146. S3 Intelligent-Tiering para storage eficiente
147. Lifecycle policies para remover dados antigos
148. CDN para reduzir tráfego desnecessário
149. Cache para reduzir compute
150. Spot instances (aproveitar capacidade ociosa)
151. Container density otimizado (menos hosts)
152. Kubernetes cluster consolidation
153. Lambda com ARM (Graviton)
154. RDS Proxy para connection pooling eficiente
155. Aurora Serverless para workloads variáveis
156. Batch processing em vez de real-time desnecessário
157. Compressão de dados (reduzir storage/transfer)
158. Deduplicação de dados
159. Monitoring para identificar waste
160. Carbon footprint tracking (Customer Carbon Footprint Tool)
```

---

## 2. Terraform & IaC

### Quando usar
- Provisionar infraestrutura AWS/GCP/Azure
- Versionamento de infraestrutura
- Ambientes reproduzíveis (dev/stage/prod)
- Rollback de mudanças de infra
- Auditoria de mudanças

### 2.1 Fundamentos
```hcl
# Casos práticos (60+):
161. Remote state obrigatório (S3 + DynamoDB lock)
162. State encryption habilitado (S3 encryption)
163. State versionado (S3 versioning)
164. Backend config separado por ambiente
165. Provider versions fixas (terraform.lock.hcl versionado)
166. Module versions fixas (evitar latest)
167. Variáveis com validation rules
168. Outputs para integração entre módulos
169. Data sources para lookup de recursos existentes
170. Workspaces para ambientes (ou diretórios separados)
171. Módulos locais para reutilização
172. Módulos remote do Registry
173. Módulos private registry (Spacelift, TFE)
174. Pre-commit hooks (terraform fmt, validate)
175. Naming convention consistente
176. Tagging obrigatório (Terraform tags)
177. Resource lifecycle (prevent_destroy)
178. Ignore changes para atributos gerenciados externamente
179. Conditional resources (count, for_each)
180. Dynamic blocks para listas complexas
181. Local values para DRY
182. terraform.tfvars vs ambiente específico (.tfvars)
183. Variáveis sensíveis marcadas (sensitive = true)
184. Secrets via data source (AWS Secrets Manager)
185. NEVER hardcode secrets
186. Provider alias para multi-region/multi-account
187. Depends_on quando Terraform não detecta dependência
188. Provisioners como último recurso
189. Null resource para workarounds
190. Import de recursos existentes
191. terraform state mv para reorganizar
192. terraform taint para forçar recreate
193. terraform refresh para sync state
194. terraform plan -out para review
195. terraform apply <planfile> para aplicar exato
196. terraform destroy com target para remover específico
197. terraform graph para visualizar dependências
198. terraform console para debug
199. TFLint para linting
200. Checkov/tfsec/terrascan para security scanning
201. Terratest para testes automatizados
202. Kitchen-Terraform para integration tests
203. Infracost para estimativa de custos
204. Terraform Cloud/Enterprise para colaboração
205. Spacelift para enterprise IaC management
206. Atlantis para automation em PRs
207. Sentinel/OPA para policy-as-code
208. Drift detection automatizado (Spacelift, Terraform Cloud)
209. Cost estimation obrigatório em PRs
210. Plan output em PR comment
211. Auto-apply apenas em dev
212. Manual approval para prod
213. Rollback via git revert + apply
214. Blue/green infra deploy
215. Feature flags em IaC (count/for_each)
216. Módulo wrapper para padronização
217. Terraform-docs para documentação automática
218. README gerado automaticamente
219. Diagrams gerados automaticamente (terraform-visual)
220. CI/CD pipeline para Terraform
```

### 2.2 Módulos AWS Terraform
```bash
# Casos práticos (50+) - usar módulos oficiais:
221. VPC: terraform-aws-modules/vpc/aws
222. EKS: terraform-aws-modules/eks/aws
223. RDS: terraform-aws-modules/rds/aws
224. ALB: terraform-aws-modules/alb/aws
225. S3: terraform-aws-modules/s3-bucket/aws
226. IAM: terraform-aws-modules/iam/aws
227. Security Group: terraform-aws-modules/security-group/aws
228. Lambda: terraform-aws-modules/lambda/aws
229. API Gateway: terraform-aws-modules/apigateway-v2/aws
230. CloudFront: terraform-aws-modules/cloudfront/aws
231. Route53: terraform-aws-modules/route53/aws
232. ACM: terraform-aws-modules/acm/aws
233. KMS: terraform-aws-modules/kms/aws
234. Secrets Manager: custom module
235. DynamoDB: terraform-aws-modules/dynamodb-table/aws
236. SNS: terraform-aws-modules/sns/aws
237. SQS: terraform-aws-modules/sqs/aws
238. EventBridge: terraform-aws-modules/eventbridge/aws
239. Step Functions: custom module
240. ECS: terraform-aws-modules/ecs/aws
241. Fargate: usando módulo ECS
242. ECR: terraform-aws-modules/ecr/aws
243. ElastiCache: custom module
244. OpenSearch: custom module
245. Kinesis: custom module
246. MSK (Kafka): custom module
247. Glue: custom module
248. Athena: custom module
249. EMR: custom module
250. SageMaker: custom module
251. CloudWatch: terraform-aws-modules/cloudwatch/aws
252. GuardDuty: custom module
253. SecurityHub: custom module
254. Config: custom module
255. SSM Parameter Store: custom module
256. Systems Manager: custom module
257. Organizations: custom module
258. Control Tower: custom module (terraform-aws-modules/control-tower)
259. Service Control Policies: custom module
260. Backup: terraform-aws-modules/backup/aws
261. WAF: terraform-aws-modules/waf/aws
262. Shield: custom module
263. VPN: terraform-aws-modules/vpn-gateway/aws
264. Direct Connect: custom module
265. Transit Gateway: terraform-aws-modules/transit-gateway/aws
266. VPC Peering: custom module
267. PrivateLink: custom module
268. VPC Endpoints: custom module
269. NAT Gateway: incluído no módulo VPC
270. Bastion Host: custom module
```

---

## 3. Kubernetes & EKS

### Quando usar
- Orquestração de containers em produção
- Multi-tenancy com namespaces
- Auto-scaling horizontal e vertical
- Service mesh para observabilidade
- GitOps para deployment

### 3.1 Fundamentos Kubernetes
```yaml
# Casos práticos (80+):
271. Pod: unidade mínima, nunca criar diretamente em prod
272. Deployment: rolling updates, rollback, replica management
273. ReplicaSet: criado automaticamente pelo Deployment
274. StatefulSet: para apps stateful (DB, Kafka, etc)
275. DaemonSet: um pod por node (monitoring agents)
276. Job: execução única
277. CronJob: execução agendada
278. Service ClusterIP: acesso interno ao cluster
279. Service NodePort: expor em porta dos nodes (dev apenas)
280. Service LoadBalancer: criar ELB/ALB automaticamente
281. Ingress: roteamento HTTP/HTTPS inteligente
282. Gateway API: substituição moderna do Ingress
283. ConfigMap: configurações não-sensíveis
284. Secret: dados sensíveis (base64, não seguro sem encryption)
285. Volume: persistência efêmera
286. PersistentVolume: persistência permanente
287. PersistentVolumeClaim: requisição de storage
288. StorageClass: provisioning dinâmico (GP3, EFS, EBS)
289. Namespace: isolamento lógico multi-tenant
290. ResourceQuota: limitar recursos por namespace
291. LimitRange: limitar recursos por pod/container
292. PodDisruptionBudget: garantir mínimo de pods disponíveis
293. HorizontalPodAutoscaler: escalar baseado em métricas
294. VerticalPodAutoscaler: ajustar requests/limits automaticamente
295. Liveness probe: detectar deadlock, reiniciar pod
296. Readiness probe: detectar quando pod está pronto para tráfego
297. Startup probe: para apps com startup lento
298. Resource requests: garantia de recursos
299. Resource limits: máximo de recursos
300. QoS classes: Guaranteed, Burstable, BestEffort
301. Node affinity: preferir certos nodes
302. Pod affinity: colocar pods próximos
303. Pod anti-affinity: separar pods (HA)
304. Taints e Tolerations: reservar nodes para workloads específicos
305. Node selector: selecionar nodes por label
306. Priority class: priorizar pods críticos
307. ServiceAccount: identidade para pods
308. RBAC: Role, ClusterRole, RoleBinding, ClusterRoleBinding
309. Network Policies: firewall entre pods
310. Pod Security Standards: Privileged, Baseline, Restricted
311. Pod Security Admission: enforce policies
312. Security Context: runAsNonRoot, readOnlyRootFilesystem
313. Capabilities: adicionar/remover Linux capabilities
314. AppArmor/Seccomp: profiles de segurança
315. Admission Controllers: validar/mutar recursos na criação
316. ValidatingWebhook: validação customizada
317. MutatingWebhook: mutação customizada (inject sidecars)
318. OPA Gatekeeper: policy-as-code
319. Kyverno: alternative to OPA, mais simples
320. Custom Resource Definitions (CRD): estender API do K8s
321. Operators: automação com reconciliation loop
322. Helm: package manager, templates, releases
323. Kustomize: overlay de manifests sem templating
324. ArgoCD: GitOps continuous deployment
325. Flux: GitOps alternative
326. kubectl: CLI principal
327. kubectx/kubens: switch context/namespace rápido
328. k9s: terminal UI para K8s
329. Lens: desktop GUI para K8s
330. Stern: tail logs de múltiplos pods
331. kubetail: similar ao stern
332. kube-capacity: ver resource usage
333. kube-ps1: mostrar context/namespace no prompt
334. kubectl debug: debug de pods com ephemeral containers
335. kubectl top: resource usage
336. kubectl explain: documentação inline
337. kubectl diff: comparar antes de apply
338. kubectl apply --dry-run=client: validar YAML
339. kubectl apply --server-dry-run: validar com admission controllers
340. kubectl rollout status: acompanhar rollout
341. kubectl rollout undo: rollback de deployment
342. kubectl scale: escalar manualmente
343. kubectl autoscale: criar HPA
344. kubectl expose: criar Service
345. kubectl exec: executar comando em pod
346. kubectl port-forward: acesso local a pod/service
347. kubectl cp: copiar arquivos para/de pod
348. kubectl logs: ver logs de pod
349. kubectl describe: detalhes de recursos
350. kubectl get events: ver eventos do cluster
```

### 3.2 EKS Específico
```bash
# Casos práticos (50+):
351. EKS cluster com Terraform (terraform-aws-modules/eks/aws)
352. EKS Auto Mode: managed nodes sem gerenciar node groups
353. Managed Node Groups: AWS gerencia nodes
354. Self-managed Node Groups: controle total
355. Fargate profiles: serverless pods
356. Karpenter: autoscaling inteligente de nodes
357. Cluster Autoscaler: autoscaling tradicional
358. IRSA (IAM Roles for Service Accounts): acesso AWS sem keys
359. EKS Pod Identity: alternativa moderna ao IRSA
360. VPC CNI: networking nativo AWS
361. Calico: network policies avançadas
362. Cilium: eBPF-based networking
363. AWS Load Balancer Controller: criar ALB/NLB via Ingress
364. External DNS: sincronizar Services com Route53
365. EBS CSI driver: volumes EBS dinâmicos
366. EFS CSI driver: shared filesystem
367. FSx CSI driver: Lustre, NetApp ONTAP
368. Secrets Store CSI driver: montar Secrets Manager como volume
369. External Secrets Operator: sync secrets automaticamente
370. cert-manager: certificados TLS automatizados
371. Metrics Server: resource metrics para HPA
372. Prometheus: métricas detalhadas
373. Grafana: dashboards de métricas
374. CloudWatch Container Insights: métricas nativas AWS
375. Fluent Bit: shipping de logs para CloudWatch
376. Loki: log aggregation
377. Jaeger: distributed tracing
378. X-Ray: tracing nativo AWS
379. OpenTelemetry: observabilidade unificada
380. Service Mesh (Istio/Linkerd): traffic management, mTLS
381. App Mesh: service mesh nativo AWS
382. Argo Rollouts: progressive delivery (canary/blue-green)
383. Flagger: progressive delivery alternativo
384. Velero: backup/restore de cluster
385. Kasten K10: backup enterprise
386. Cluster API: gerenciar clusters como recursos K8s
387. Crossplane: provisionar infra AWS via K8s
388. ACK (AWS Controllers for Kubernetes): manage AWS via K8s
389. KubeVirt: rodar VMs em K8s (workloads legacy)
390. Knative: serverless workloads em K8s
391. Tekton: CI/CD pipelines nativos K8s
392. Argo Workflows: workflow engine
393. Kubeflow: ML workloads
394. Spark on Kubernetes: big data processing
395. KubeFed: federar múltiplos clusters
396. Submariner: conectar clusters multi-cloud
397. Goldilocks: recomendações de resource requests/limits
398. Fairwinds Insights: security/governance scanning
399. Kube-bench: CIS benchmark compliance
400. Popeye: cluster sanity checks
```

---

## 4. CI/CD Pipelines

### Quando usar
- Automatizar build/test/deploy
- Garantir qualidade de código
- Deploy seguro em produção
- Rollback rápido em caso de falha

### 4.1 GitHub Actions
```yaml
# Casos práticos (60+):
401. Workflow trigger on push/pull_request
402. Workflow dispatch manual
403. Schedule cron jobs
404. Matrix strategy para multi-version testing
405. Reusable workflows para DRY
406. Composite actions para steps reutilizáveis
407. Docker layer caching com actions/cache
408. Artifact upload/download entre jobs
409. Secrets management com GitHub Secrets
410. Environment secrets para dev/stage/prod
411. OIDC para AWS (sem access keys)
412. aws-actions/configure-aws-credentials
413. docker/build-push-action para build/push eficiente
414. Multi-platform builds (amd64, arm64)
415. Terraform plan em PR comment
416. Terraform apply automático em merge (dev)
417. Manual approval para prod (environment protection)
418. kubectl apply via GitHub Actions
419. Helm deploy via GitHub Actions
420. ArgoCD sync via GitHub Actions
421. Linting (ESLint, Pylint, golangci-lint)
422. Unit tests com coverage report
423. Integration tests
424. E2E tests
425. Security scanning (Trivy, Snyk)
426. SAST (Semgrep, CodeQL)
427. DAST (OWASP ZAP)
428. Dependency scanning (Dependabot)
429. Container image scanning
430. IaC scanning (Checkov, tfsec)
431. Code quality gates (SonarQube)
432. Performance tests (k6, Locust)
433. Smoke tests pós-deploy
434. Rollback automático em falha
435. Slack notification de deploy
436. GitHub Status Checks obrigatórios
437. Branch protection rules
438. CODEOWNERS para review automático
439. Auto-merge com checks passed
440. Label-based automation
441. Issue/PR templates
442. Conventional commits enforcement
443. Semantic versioning automático
444. Changelog gerado automaticamente
445. Release notes automáticas
446. Docker image tagging strategy
447. Git tags para releases
448. Deploy preview em PR (ephemeral env)
449. Cost estimation comment em Terraform PR
450. Diff visible no PR para Terraform/Kubernetes
451. Parallel jobs para speed
452. Job dependencies (needs)
453. Conditional steps (if)
454. Timeout configurado em jobs
455. Retry failed jobs automaticamente
456. Self-hosted runners (economizar custos, acesso privado)
457. Runner scaling automático (ARC - Actions Runner Controller)
458. GitHub Packages como registry
459. GitHub Container Registry (GHCR)
460. ECR integration
```

### 4.2 Azure DevOps Pipelines
```yaml
# Casos práticos (30+):
461. YAML pipelines (não classic UI)
462. Multi-stage pipelines (build, test, deploy)
463. Templates para reutilização
464. Pipeline as Code
465. Self-hosted agents (economizar custos, VNet acesso)
466. Agent pools dedicados por ambiente
467. Service connections com OIDC para AWS
468. Variable groups para secrets
469. Azure Key Vault integration
470. Terraform backend em Azure Storage
471. Terraform plan/apply stages
472. Kubernetes deploy tasks
473. Helm chart deploy
474. Docker build/push
475. Multi-platform container builds
476. Artifact publish/download
477. Pipeline caching
478. Test results publishing
479. Code coverage reporting
480. Security scanning integration
481. Approval gates para prod
482. Manual intervention
483. Deployment slots (blue/green)
484. Canary deployment
485. Ring deployment strategy
486. Rollback trigger automático
487. Pipeline analytics
488. Release dashboard
489. Wiki para documentação de pipelines
490. Work item integration (link commits/PRs)
```

### 4.3 Jenkins
```groovy
# Casos práticos (30+):
491. Declarative Pipeline (não Scripted)
492. Jenkinsfile in repo (Pipeline as Code)
493. Multi-branch pipeline
494. Shared library para reutilização
495. Credentials management (não hardcode)
496. AWS credentials binding
497. Docker plugin para builds em containers
498. Kubernetes plugin para dynamic agents
499. Blue Ocean UI (melhor UX)
500. Pipeline stage view
501. Build triggers (SCM polling, webhook)
502. Cron triggers
503. Parallel stages para speed
504. Stash/unstash para artifacts
505. Archiving artifacts
506. JUnit test results
507. Code coverage plugins (JaCoCo)
508. SonarQube integration
509. Security scanning plugins
510. Slack notifications
511. Email notifications
512. Build status badge
513. Rollback logic em pipeline
514. Input step para approval manual
515. Retry failed steps
516. Timeout em stages
517. Post-build cleanup
518. Workspace cleanup
519. Agent label para selecionar nodes específicos
520. Jenkins Configuration as Code (JCasC)
```

---

## 5. FinOps & Cost Optimization

### Quando usar
- Reduzir custos AWS sem impactar performance
- Forecasting de gastos
- Chargeback por equipe/projeto
- Otimizar Reserved Instances / Savings Plans

### 5.1 Cost Optimization Strategies
```bash
# Casos práticos (80+):
521. Cost Explorer para análise de gastos
522. Cost Allocation Tags obrigatórios (projeto, equipe, ambiente)
523. Budgets com alertas (SNS, email)
524. Budgets com actions (stop instances)
525. Cost Anomaly Detection habilitado
526. Trusted Advisor checks habilitados
527. Compute Optimizer para rightsizing recommendations
528. Reserved Instance recommendations (Cost Explorer)
529. Savings Plans recommendations (Cost Explorer)
530. RI/SP Coverage reportado semanalmente
531. RI/SP Utilization monitorado
532. Spot instance adoption para workloads tolerantes
533. Spot fleet com fallback On-Demand
534. EC2 Instance Scheduler (desligar dev/test fora do horário)
535. Lambda para stop/start automático
536. EventBridge rules para scheduling
537. RDS stop/start scheduling
538. RDS automated snapshots antes de stop
539. Aurora Serverless v2 para dev/test
540. Fargate Spot para ECS/EKS non-prod
541. S3 Lifecycle policies para Glacier/Deep Archive
542. S3 Intelligent-Tiering automático
543. S3 Storage Class Analysis
544. S3 Inventory para análise de objetos
545. EBS GP3 migration de GP2 (30% mais barato)
546. EBS snapshot lifecycle policy
547. Remover EBS volumes não usados (script)
548. Remover snapshots órfãos (volumes deletados)
549. Elastic IP não associado (cobrança)
550. NAT Gateway vs NAT Instance (custo/performance trade-off)
551. VPC Endpoints para reduzir NAT Gateway usage
552. CloudFront cache otimizado (menos origin requests)
553. Lambda memory sizing (profiling)
554. Lambda Provisioned Concurrency apenas se necessário
555. Lambda ARM (Graviton, 20% mais barato)
556. API Gateway caching habilitado
557. ElastiCache para reduzir DB load
558. RDS read replicas vs query optimization
559. DynamoDB on-demand vs provisioned (padrão de acesso)
560. DynamoDB auto-scaling para provisioned mode
561. DynamoDB TTL para cleanup automático
562. OpenSearch reserved instances
563. Redshift reserved nodes
564. Redshift pause/resume automático
565. Athena query optimization (partition, compress)
566. Glue job optimization (DPU sizing)
567. EMR cluster rightsizing
568. EMR Spot instances para data processing
569. SageMaker instance rightsizing
570. SageMaker inference endpoints auto-scaling
571. EKS cost optimization (Kubecost, OpenCost)
572. Karpenter consolidation policy
573. Container image optimization (smaller = faster = cheaper)
574. Multi-tenancy em cluster (reduzir clusters)
575. Namespace resource quotas (evitar overprovisioning)
576. Vertical Pod Autoscaler (VPA) para tuning
577. Cluster Autoscaler scale-down policy agressivo (non-prod)
578. Spot instances em node groups não-críticos
579. Graviton nodes no EKS (30-40% mais barato)
580. Fargate vs EC2 nodes (custo por workload)
581. CloudWatch Logs retention policy
582. CloudWatch Logs filtering antes de ingestar
583. CloudWatch Metrics resolution (1m vs 5m)
584. VPC Flow Logs para S3 (não CloudWatch Logs)
585. GuardDuty findings exportados para S3 (menos custo)
586. Config snapshot to S3 (não manter tudo em service)
587. CloudTrail log file validation
588. CloudTrail multi-region in one trail
589. Data Transfer costs analysis (maior fonte de surpresa!)
590. Inter-AZ transfer costs (considerar arquitetura)
591. Inter-region transfer costs (replication)
592. CloudFront vs direto S3 (transfer out mais barato)
593. Global Accelerator vs CloudFront (use case)
594. Direct Connect vs VPN (volume de dados)
595. Cost of idle resources (dashboard)
596. Unused Load Balancers (remover)
597. Unused Elastic IPs (remover)
598. Unused AMIs (cleanup policy)
599. Unused security groups (cleanup)
600. FinOps culture: visibility, accountability, optimization
```

---

## 6. Networking AWS

### Quando usar
- Troubleshoot connectivity issues
- Design de rede segura
- Multi-VPC connectivity
- Hybrid cloud (on-premise + AWS)

### 6.1 VPC & Networking
```bash
# Casos práticos (60+):
601. VPC com CIDR adequado (/16 para flexibilidade)
602. Subnets públicas vs privadas
603. Route Tables: public (IGW), private (NAT Gateway)
604. Internet Gateway (IGW) uma por VPC
605. NAT Gateway em subnet pública (HA: uma por AZ)
606. NAT Instance para economizar (menor throughput)
607. Egress-only Internet Gateway (IPv6)
608. VPC Peering: conectar VPCs (não transitivo)
609. Transit Gateway: hub central multi-VPC
610. Transit Gateway route tables
611. Transit Gateway attachments
612. VPN Connection para on-premise
613. Customer Gateway (on-premise lado)
614. Virtual Private Gateway (AWS lado VPN)
615. Direct Connect para conexão dedicada
616. Direct Connect Gateway para multi-region
617. VPC Endpoints: Interface (ENI) vs Gateway (route table)
618. VPC Endpoint para S3 (grátis, reduz NAT Gateway)
619. VPC Endpoint para DynamoDB (grátis)
620. PrivateLink para serviços third-party
621. Security Groups: stateful, whitelist, source pode ser SG
622. NACL: stateless, subnet-level, menos usado
623. VPC Flow Logs: troubleshooting, auditoria
624. Flow Logs para S3 (custo) vs CloudWatch Logs
625. Flow Logs filtrados (reduzir custo)
626. Route53: DNS privado para VPC
627. Route53 Resolver: hybrid DNS (on-premise)
628. Route53 health checks para failover
629. ELB: Classic, Application, Network, Gateway
630. ALB: Layer 7, path-based routing, host-based routing
631. ALB target groups: IP, instance, Lambda
632. ALB listener rules (priority)
633. ALB SSL/TLS termination
634. NLB: Layer 4, ultra-low latency, static IP
635. NLB Preserve source IP
636. NLB Cross-zone load balancing
637. GWLB: para appliances de rede (firewall, IDS)
638. ALB + WAF para proteção web
639. ALB + Shield para DDoS protection
640. ALB Access Logs para auditoria
641. ALB desync mitigation mode
642. ALB slow loris protection
643. Security Group para ALB: permitir apenas CloudFront IPs (se uso)
644. Target Group health checks configurados corretamente
645. Deregistration delay configurado (drain connections)
646. Connection idle timeout configurado
647. Sticky sessions (session affinity) quando necessário
648. ALB vs NLB: caso de uso correto
649. Cross-zone load balancing habilitado (distribuição)
650. Multi-AZ deployment obrigatório para HA
651. Bastion Host em subnet pública (SSH)
652. SSM Session Manager em vez de Bastion (mais seguro)
653. VPN Client-to-Site (AWS Client VPN)
654. VPN Site-to-Site (on-premise to AWS)
655. VPN redundancy (múltiplos tunnels)
656. BGP over VPN para roteamento dinâmico
657. IP addressing: não sobrepor CIDRs entre VPCs
658. Subnetting strategy por função (app, data, mgmt)
659. Reserved IPs em subnet (5 IPs por subnet)
660. Elastic Network Interface (ENI) para IP fixo
```

### 6.2 Troubleshooting Network
```bash
# Casos práticos (40+):
661. Timeout: verificar Security Group
662. Timeout: verificar NACL
663. Timeout: verificar Route Table
664. Timeout: verificar Target Group health check
665. Connection refused: app não está listening
666. 403 Forbidden: verificar IAM policy, bucket policy, VPC Endpoint policy
667. 403 no S3: verificar VPC Endpoint policy statement
668. 403 no API Gateway private: verificar resource policy
669. DNS não resolve: verificar Route53 Hosted Zone
670. DNS não resolve interno: habilitar enableDnsHostnames e enableDnsSupport
671. Inter-VPC não funciona: VPC Peering routes configuradas?
672. Transit Gateway não funciona: attachment em subnet correta?
673. VPN não conecta: verificar Customer Gateway BGP ASN
674. VPN instável: verificar MTU (1500 vs 1400)
675. Direct Connect down: verificar BGP status
676. NAT Gateway não funciona: está em subnet pública? Route table correto?
677. IGW não funciona: attached na VPC?
678. ELB 502: target unhealthy, verificar health check
679. ELB 503: no targets available
680. ELB 504 Gateway Timeout: target slow, aumentar timeout
681. ALB 404: verificar listener rules, priority
682. NLB não distribui: cross-zone desabilitado
683. VPC Flow Logs REJECT: identificar Security Group/NACL bloqueando
684. tcpdump em EC2 para análise de pacotes
685. curl/telnet para testar conectividade
686. dig/nslookup para troubleshoot DNS
687. traceroute para ver path de rede
688. mtr para troubleshooting de latência
689. AWS Reachability Analyzer: validar path de rede
690. VPC Flow Logs Insights: query CloudWatch Logs
691. CloudWatch Metrics para ALB/NLB
692. Access Logs do ALB para debug de requests
693. Packet capture (espelhar tráfego para análise)
694. Network Load Balancer TLS passthrough vs termination
695. PrivateLink connection timeout: verificar VPC Endpoint service
696. Interface Endpoint DNS: usar DNS privado
697. Security Group referencing: SG pode ser source/destination
698. Security Group chaining para micro-segmentation
699. NACL: regras numeradas, avaliadas em ordem
700. NACL: lembrar de permitir ephemeral ports (1024-65535)
```

---

## 7. Observabilidade

### Quando usar
- Monitorar saúde de aplicações
- Detectar issues proativamente
- Debug de performance
- Alertas de SLO breach

### 7.1 Logs, Metrics, Traces
```bash
# Casos práticos (60+):
701. CloudWatch Logs para logs centralizados
702. CloudWatch Logs Insights para queries
703. CloudWatch Logs subscription filter para streaming
704. CloudWatch Logs retention policy
705. CloudWatch Metrics para métricas custom
706. CloudWatch Alarms para alertas
707. CloudWatch Dashboard para visualização
708. CloudWatch Synthetics para testes sintéticos
709. CloudWatch RUM (Real User Monitoring)
710. CloudWatch Application Insights
711. CloudWatch Container Insights (ECS/EKS)
712. CloudWatch Lambda Insights
713. X-Ray para distributed tracing
714. X-Ray SDK integration
715. X-Ray service map
716. X-Ray trace analysis
717. Prometheus para métricas K8s
718. Prometheus Operator para deploy
719. Prometheus ServiceMonitor para scraping
720. Prometheus PodMonitor
721. Prometheus recording rules (pre-aggregate)
722. Prometheus alerting rules
723. Alertmanager para roteamento de alertas
724. Alertmanager silences para manutenção
725. Alertmanager receiver (Slack, PagerDuty, email)
726. Grafana para dashboards
727. Grafana datasources (Prometheus, CloudWatch, Loki)
728. Grafana dashboards pré-construídos (importar)
729. Grafana alerts (alternativa Alertmanager)
730. Grafana OnCall para on-call management
731. Loki para log aggregation
732. Promtail para shipping logs para Loki
733. Fluent Bit para shipping logs (CloudWatch, Loki)
734. Fluentd: alternativa ao Fluent Bit
735. Logstash: parte do ELK stack
736. Elasticsearch para indexação de logs
737. Kibana para visualização de logs
738. OpenSearch: alternativa open-source ao Elasticsearch
739. Jaeger para distributed tracing
740. Jaeger all-in-one para dev
741. Jaeger production deployment (Cassandra/Elasticsearch backend)
742. OpenTelemetry: padrão unificado (metrics, logs, traces)
743. OTEL Collector: receber, processar, exportar telemetria
744. OTEL auto-instrumentation para apps
745. OTEL SDK integration
746. Datadog: plataforma completa de observabilidade
747. Datadog APM para tracing
748. Datadog Logs
749. Datadog Infrastructure Monitoring
750. Datadog RUM
751. Datadog Synthetics
752. New Relic: alternativa ao Datadog
753. Dynatrace: APM enterprise
754. Honeycomb: observability com high-cardinality data
755. Lightstep: tracing e observability
756. Sentry: error tracking
757. Rollbar: error tracking alternativo
758. PagerDuty para incident management
759. Opsgenie: alternativa ao PagerDuty
760. SLO/SLI definidos e monitorados
```

### 7.2 Alerting Best Practices
```bash
# Casos práticos (40+):
761. Alertas devem ser actionable (não ruído)
762. Definir severidade: Critical, Warning, Info
763. Critical: acorda on-call, quebra SLO
764. Warning: investigar dentro de horas
765. Info: conhecimento, não ação
766. Runbook URL em alert (como resolver)
767. Contexto suficiente em alert message
768. Alert fatigue: muito alerta = ignorar
769. Alert aggregation (não spammar)
770. Alert inhibition (suprimir dependentes)
771. Alert silencing para manutenção programada
772. Auto-resolve alerts quando métrica normaliza
773. Escalation policy (time-based)
774. Primary/secondary on-call rotation
775. Follow-the-sun on-call (multi-region teams)
776. PagerDuty integration com Slack
777. Slack bot para acknowledge/resolve incidents
778. Incident timeline tracking
779. Postmortem automatizado (template)
780. Blameless postmortem culture
781. SLO-based alerting (error budget burn rate)
782. Multi-window multi-burn-rate alerting
783. Alerting on prediction (going to breach SLO)
784. Capacity alerting (disk 80% full, crescendo)
785. Saturation metrics (resource approaching limit)
786. Error rate % vs absolute count
787. Latency P50, P95, P99 (não só média)
788. Success rate vs error rate
789. Request rate (RPS, QPM)
790. Dependency health checks
791. Synthetic monitoring (teste endpoint cada 5min)
792. Canary testing (deploy canary, monitorar, rollback se metrics ruins)
793. Shadow traffic (duplicate real traffic, comparar responses)
794. Chaos engineering (inject failures, ver se alertas funcionam)
795. Alert testing (fire test alert, verificar se chega)
796. Oncall handoff documentation
797. Incident retrospective (learn from incidents)
798. Metrics dashboard no TV do escritório
799. Status page público (uptimerobot, statuspage.io)
800. Internal status page (Grafana dashboard, pública internamente)
```

---

## 8. Secrets Management

### Quando usar
- Armazenar credenciais com segurança
- Rotação automática de secrets
- Auditoria de acesso a secrets
- Integração com aplicações sem hardcode

### 8.1 AWS Secrets Manager
```bash
# Casos práticos (40+):
801. Secrets Manager para DB credentials
802. Automatic rotation habilitado (Lambda function)
803. Rotation schedule (30 dias)
804. Secret versioning automático
805. Secret policy para controle de acesso
806. Replica secret para multi-region
807. Integration com RDS (automático)
808. Integration com Redshift
809. Custom secret (API keys, tokens)
810. Binary secrets (certificates)
811. CloudTrail logging de acessos
812. KMS encryption obrigatório (CMK)
813. Resource policy em secret (quem pode acessar)
814. Tag-based access control
815. VPC Endpoint para acesso privado (sem internet)
816. Lambda retrieve secret (boto3)
817. ECS task retrieve secret (secretsmanager log driver)
818. EKS retrieve via External Secrets Operator
819. EKS retrieve via Secrets Store CSI driver
820. Terraform data source para lookup secret
821. Never print secret em logs
822. Environment variable sem secret exposto
823. Secret caching para reduzir calls (custo)
824. Secret rotation testing automatizado
825. Alert quando rotation falha
826. Backup de secrets (Terraform state tem ref, não valor)
827. Cross-account secret access (resource policy)
828. Least privilege IAM policy (GetSecretValue específico)
829. Condition keys para controle fino
830. MFA required para secret específico
831. Cost optimization: deletar secrets não usados
832. Scheduled deletion (7-30 dias, recuperável)
833. Replica para DR region
834. Secret versioning stages: AWSCURRENT, AWSPENDING, AWSPREVIOUS
835. Rollback secret para versão anterior
836. Audit trail de mudanças
837. Secret metadata (description, tags)
838. Terraform: sensitive = true para secret
839. Pre-commit hook: bloquear commit de secret
840. Git-secrets tool (prevent commit secret)
```

### 8.2 SSM Parameter Store
```bash
# Casos práticos (30+):
841. Parameter Store para config não-sensível
842. SecureString (KMS encrypted) para sensível
843. Standard tier (free, 10k params, 4KB size)
844. Advanced tier (custo, 100k params, 8KB size)
845. Parameter hierarchies (/prod/db/password)
846. GetParametersByPath para bulk retrieve
847. Parameter policies (expiration, notification)
848. Parameter versioning (até 100 versões)
849. Parameter labels para alias (latest, stable)
850. CloudTrail logging de acessos
851. VPC Endpoint para acesso privado
852. IAM policy para GetParameter
853. Condition key: ssm:ResourceTag/<key>
854. Tag-based access control
855. Terraform data source para lookup parameter
856. Lambda retrieve parameter (boto3 SSM)
857. ECS task retrieve parameter (valueFrom: ssm)
858. EKS retrieve via External Secrets Operator
859. User Data script retrieve parameter (aws ssm get-parameter)
860. CloudFormation dynamic reference (resolve:ssm)
861. CodeBuild environment variable from SSM
862. Systems Manager Automation para rotação
863. Parameter change triggers Lambda (EventBridge)
864. Notification via SNS quando parameter expira
865. Parameter Store vs Secrets Manager (custo vs features)
866. Parameter Store free tier (10k standard params)
867. Secrets Manager custo: $0.40/secret/month + API calls
868. Migrate from Parameter Store to Secrets Manager (automation)
869. Hybrid: config em Parameter Store, secrets em Secrets Manager
870. Backup parameters (AWS Backup não suporta, usar script)
```

### 8.3 HashiCorp Vault
```bash
# Casos práticos (30+):
871. Vault para secrets multi-cloud
872. Vault on Kubernetes (Helm chart)
873. Vault Agent Injector (sidecar)
874. Vault CSI provider (mount secrets as volumes)
875. Vault dynamic secrets (DB credentials on-demand)
876. Vault secret engines (KV, DB, AWS, PKI)
877. Vault AWS auth method (IAM authentication)
878. Vault Kubernetes auth method
879. Vault policies para RBAC
880. Vault namespaces para multi-tenancy
881. Vault HA setup (Raft, Consul backend)
882. Vault auto-unseal (AWS KMS, GCP KMS)
883. Vault audit logging
884. Vault secret versioning
885. Vault lease renewal (dynamic secrets)
886. Vault secret rotation
887. Vault Transit engine (encryption as a service)
888. Vault PKI engine (certificate authority)
889. Vault SSH engine (SSH certificate authority)
890. Vault response wrapping (secure secret delivery)
891. Vault AppRole for CI/CD
892. Vault OIDC auth for humans
893. Vault MFA for sensitive operations
894. Vault Sentinel policies (enterprise)
895. Vault performance replication (enterprise)
896. Vault DR replication (enterprise)
897. Vault backup (snapshot)
898. Vault upgrade strategy (blue/green)
899. Cost: open-source vs enterprise
900. Vault vs AWS Secrets Manager (trade-offs)
```

---

## 9. GitOps

### Quando usar
- Deploy declarativo via Git
- Auditoria de mudanças (Git history)
- Rollback fácil (git revert)
- Self-healing de infra/apps

### 9.1 ArgoCD
```yaml
# Casos práticos (50+):
901. ArgoCD install via Helm
902. ArgoCD Application CRD
903. ArgoCD Project para multi-tenancy
904. ArgoCD sync policy (auto vs manual)
905. ArgoCD prune (remover resources não declarados)
906. ArgoCD self-heal (corrigir drift automático)
907. ArgoCD sync waves (ordem de deploy)
908. ArgoCD sync hooks (PreSync, PostSync)
909. ArgoCD health checks custom
910. ArgoCD notification (Slack, email)
911. ArgoCD SSO (OIDC, SAML)
912. ArgoCD RBAC policies
913. ArgoCD multi-cluster management
914. ArgoCD ApplicationSet (templatizar Apps)
915. ArgoCD ApplicationSet generators (Git, List, Matrix)
916. ArgoCD Image Updater (auto-update image tag)
917. ArgoCD Rollouts (progressive delivery)
918. ArgoCD Rollouts analysis (metrics-based rollback)
919. ArgoCD Rollouts blue/green
920. ArgoCD Rollouts canary
921. ArgoCD Rollouts traffic splitting
922. ArgoCD CLI (argocd app sync)
923. ArgoCD UI dashboard
924. ArgoCD API for automation
925. ArgoCD Vault plugin (inject secrets)
926. ArgoCD KSOPS plugin (encrypt secrets in Git)
927. ArgoCD Helm integration
928. ArgoCD Kustomize integration
929. ArgoCD Jsonnet support
930. ArgoCD config management plugin (custom)
931. ArgoCD repo server scaling
932. ArgoCD application controller scaling
933. ArgoCD redis HA
934. ArgoCD backup (export resources, Git is source of truth)
935. ArgoCD upgrade strategy
936. ArgoCD vs Flux (trade-offs)
937. ArgoCD metrics (Prometheus)
938. ArgoCD dashboard grafana
939. ArgoCD webhook trigger (GitHub, GitLab)
940. ArgoCD pull vs push model (ArgoCD é pull)
941. ArgoCD sync timeout configuration
942. ArgoCD ignore differences (known drift OK)
943. ArgoCD resource tracking (label, annotation)
944. ArgoCD orphaned resources detection
945. ArgoCD out-of-sync detection
946. ArgoCD diff view (before sync)
947. ArgoCD rollback (revert Git commit + sync)
948. ArgoCD monorepo support
949. ArgoCD multiple sources (Helm + Kustomize)
950. ArgoCD cost: open-source, sem licenciamento
```

---

## 10. Security & DevSecOps

### Quando usar
- Shift-left security (early detection)
- Compliance automatizado
- Auditoria de acessos
- Vulnerabilidade scanning

### 10.1 Security Scanning
```bash
# Casos práticos (50+):
951. Trivy: scan container images
952. Trivy: scan IaC (Terraform, CloudFormation)
953. Trivy: scan Kubernetes manifests
954. Trivy in CI/CD pipeline
955. Snyk: scan dependencies
956. Snyk: scan container images
957. Snyk: scan IaC
958. Snyk fix (auto-fix vulnerabilities)
959. Checkov: scan Terraform
960. Checkov custom policies
961. tfsec: Terraform security scanner
962. terrascan: multi-IaC scanner
963. KICS: IaC security scanner
964. Semgrep: SAST (Static Analysis)
965. Semgrep rules customization
966. CodeQL: GitHub native SAST
967. SonarQube: code quality + security
968. OWASP Dependency-Check
969. Retire.js: scan JS dependencies
970. Gitleaks: scan for secrets in Git history
971. TruffleHog: secret scanning
972. git-secrets: prevent secret commit
973. pre-commit hooks para scanning
974. Hadolint: Dockerfile linting
975. Docker Bench Security
976. CIS Kubernetes Benchmark (kube-bench)
977. Falco: runtime security K8s
978. Tracee: runtime security eBPF
979. Sysdig Secure: container security
980. Aqua Security: container security
981. Prisma Cloud (Palo Alto): CSPM
982. Wiz: CSPM + CWPP
983. Orca Security: agentless scanning
984. Lacework: cloud security platform
985. GuardDuty: AWS threat detection
986. Security Hub: AWS security posture
987. Inspector: vulnerability scanning AWS
988. Macie: sensitive data discovery S3
989. Config: compliance checking AWS
990. CloudTrail: audit logging AWS
991. Access Analyzer: IAM policy validation
992. IAM Access Advisor: unused permissions
993. Prowler: AWS security assessment
994. ScoutSuite: multi-cloud security audit
995. CloudSploit: AWS security scanning
996. Steampipe: SQL queries para cloud resources
997. Policy as Code (OPA, Kyverno, Sentinel)
998. Shift-left: scan before commit
999. Shift-left: scan in PR
1000. Security gates: block PR se vulnerabilidades Critical
```

---

## 11. High Availability & Disaster Recovery

### Quando usar
- RTO/RPO requirements definidos
- Business continuity planning
- Multi-region deployment
- Backup/restore automatizado

```bash
# Casos práticos (50+):
1001. Multi-AZ deployment obrigatório
1002. Multi-region para DR (Recovery Region)
1003. Active-Active multi-region (custo alto, RTO ~0)
1004. Active-Passive multi-region (custo médio, RTO minutos)
1005. Pilot Light (infra mínima, RTO horas)
1006. Backup & Restore (custo baixo, RTO dias)
1007. Route53 health checks + failover
1008. Route53 Geoproximity routing
1009. Global Accelerator para failover automático
1010. CloudFront multi-origin failover
1011. RDS Multi-AZ (sync replication)
1012. RDS Read Replica cross-region
1013. RDS automated backups (point-in-time restore)
1014. RDS manual snapshots antes de mudanças
1015. Aurora Global Database (cross-region, <1s replication)
1016. DynamoDB Global Tables (multi-region, active-active)
1017. S3 Cross-Region Replication (CRR)
1018. S3 versioning habilitado
1019. S3 MFA delete para proteção
1020. EBS snapshots automatizados (Data Lifecycle Manager)
1021. EBS snapshots cross-region copy
1022. AMI copy para DR region
1023. AWS Backup: backup centralizado multi-service
1024. AWS Backup vault lock (compliance)
1025. AWS Backup cross-region/cross-account
1026. Velero: backup Kubernetes (EKS)
1027. Velero schedule (daily backup)
1028. Velero restore testing (quarterly)
1029. Database dump para S3 (extra layer)
1030. Point-in-time recovery testing
1031. Disaster Recovery runbook
1032. DR testing schedule (quarterly, anualmente)
1033. Game day: simular desastre completo
1034. RTO/RPO SLA documentado
1035. RTO/RPO monitoring (alert se em risco)
1036. Chaos engineering: kill AZ inteira (simulação)
1037. Circuit breaker para degradação graceful
1038. Retry com exponential backoff
1039. Timeout em todas as chamadas externas
1040. Bulkhead pattern (isolate failures)
1041. Graceful shutdown (drain connections)
1042. Health check endpoint (liveness, readiness)
1043. Load balancer health check configurado
1044. Auto Scaling health check (ELB + EC2)
1045. Immutable infrastructure (não patch, replace)
1046. Blue/green deployment (zero downtime)
1047. Canary deployment (risk mitigation)
1048. Feature flags (disable feature sem deploy)
1049. Database migration strategy (backward compatible)
1050. Rolling deployment com maxUnavailable controlado
```

---

## 12. Platform Engineering & IDP

### Quando usar
- Criar self-service para desenvolvedores
- Reduzir cognitive load de devs
- Golden paths para deploy
- Developer Experience (DevEx)

```bash
# Casos práticos (50+):
1051. Internal Developer Platform (IDP) vision
1052. Platform as Product mindset
1053. Backstage: developer portal open-source
1054. Backstage Software Catalog
1055. Backstage Software Templates (scaffolder)
1056. Backstage TechDocs (docs-as-code)
1057. Backstage Plugins ecosystem
1058. Backstage Kubernetes plugin
1059. Backstage ArgoCD plugin
1060. Backstage AWS plugin
1061. Backstage Cost Insights plugin
1062. Backstage Security Insights plugin
1063. Backstage custom plugins
1064. Service Catalog: self-service provisioning
1065. Golden paths: opinionated, best-practice templates
1066. Self-service via Terraform modules
1067. Self-service via Crossplane XRDs
1068. Self-service via Helm charts
1069. Self-service via ArgoCD ApplicationSets
1070. Self-service via Backstage templates
1071. Self-service namespace creation (K8s)
1072. Self-service RDS database provisioning
1073. Self-service S3 bucket provisioning
1074. Self-service CI/CD pipeline creation
1075. Self-service monitoring dashboard creation
1076. Self-service alerting rule creation
1077. Self-service secrets creation (Vault)
1078. Self-service SSL certificate (cert-manager)
1079. Self-service DNS record (External DNS)
1080. Self-service Ingress creation
1081. Self-service GitHub repo creation
1082. Self-service team onboarding
1083. Developer productivity metrics (DORA)
1084. Deployment frequency
1085. Lead time for changes
1086. Change failure rate
1087. Time to restore service (MTTR)
1088. Platform team vs Product teams
1089. Platform roadmap driven by product teams
1090. Feedback loop: developer surveys
1091. Developer Experience (DevEx) focus
1092. Cognitive load reduction
1093. Toil automation (repetitive tasks)
1094. Documentation central (TechDocs)
1095. Runbooks integrated in platform
1096. On-call runbook in Backstage
1097. Incident management integration (PagerDuty)
1098. ChatOps integration (Slack)
1099. Cost visibility per team (FinOps)
1100. Cost allocation automated (tags)
```

---

## 🎯 Matriz de Priorização

### Nível Iniciante (0-2 anos)
**Foco:** Fundamentos + hands-on

| Domínio | Skills Prioritárias |
|---------|---------------------|
| AWS | VPC, EC2, S3, IAM, RDS (casos 1-50) |
| Terraform | Remote state, módulos básicos, providers (161-180) |
| Kubernetes | Pods, Deployments, Services, Ingress (271-300) |
| CI/CD | GitHub Actions básico, Docker build/push (401-420) |
| Observabilidade | CloudWatch básico, logs, métricas (701-720) |

### Nível Intermediário (2-5 anos)
**Foco:** Automação + Segurança

| Domínio | Skills Prioritárias |
|---------|---------------------|
| AWS | Multi-AZ, Auto Scaling, ELB, Route53 (46-100) |
| Terraform | Módulos avançados, workspaces, drift detection (181-220) |
| Kubernetes | RBAC, Network Policies, HPA, Storage (301-350) |
| CI/CD | Multi-stage pipelines, security scanning (421-460) |
| FinOps | Cost Explorer, RI/SP, rightsizing (521-560) |
| Security | Secrets management, scanning, compliance (801-900) |

### Nível Avançado (5-10 anos)
**Foco:** Arquitetura + Otimização

| Domínio | Skills Prioritárias |
|---------|---------------------|
| AWS | Multi-region, DR, performance optimization (1001-1050) |
| Terraform | Enterprise (TFC/Spacelift), policy-as-code (200-220) |
| Kubernetes | Operators, service mesh, Karpenter (351-400) |
| CI/CD | GitOps, progressive delivery, automation (901-950) |
| FinOps | Advanced optimization, forecasting, chargeback (561-600) |
| Platform | IDP, self-service, DevEx (1051-1100) |

### Nível Especialista (10+ anos)
**Foco:** Liderança + Estratégia

| Domínio | Skills Prioritárias |
|---------|---------------------|
| Arquitetura | Well-Architected reviews, multi-cloud, hybrid |
| Governance | Organizations, Control Tower, SCPs, compliance |
| FinOps | FinOps culture, executive reporting, forecasting |
| Platform | Platform strategy, product thinking, team topology |
| Liderança | Mentoring, technical roadmap, decision frameworks |

---

## 📚 Recursos de Aprendizado

### Documentação Oficial
- [AWS Documentation](https://docs.aws.amazon.com/)
- [Terraform Registry](https://registry.terraform.io/)
- [Kubernetes Documentation](https://kubernetes.io/docs/)
- [GitHub Actions Documentation](https://docs.github.com/en/actions)

### Hands-on Labs
- [AWS Workshops](https://workshops.aws/)
- [Terraform Tutorials](https://learn.hashicorp.com/terraform)
- [Kubernetes by Example](https://kubernetesbyexample.com/)
- [Katacoda (free interactive scenarios)](https://katacoda.com/)

### Certificações Recomendadas
- **AWS**: Solutions Architect Associate/Professional, DevOps Engineer Professional
- **Kubernetes**: CKA (Certified Kubernetes Administrator), CKAD, CKS
- **Terraform**: HashiCorp Certified: Terraform Associate
- **FinOps**: FinOps Certified Practitioner

### Comunidades
- AWS re:Post
- CNCF Slack
- DevOps subreddit
- FinOps Foundation
- Platform Engineering Slack

---

## ✅ Checklist de Uso

Ao trabalhar em um projeto DevOps/Infra:

- [ ] Arquitetura segue AWS Well-Architected? (casos 1-160)
- [ ] Terraform com remote state + locking? (casos 161-170)
- [ ] Secrets gerenciados corretamente (NEVER hardcode)? (casos 801-900)
- [ ] Security scanning em CI/CD? (casos 951-1000)
- [ ] Multi-AZ deployment em prod? (casos 1001-1010)
- [ ] Observabilidade completa (logs, metrics, traces)? (casos 701-800)
- [ ] Cost optimization implementado? (casos 521-600)
- [ ] Disaster Recovery testado? (casos 1011-1050)
- [ ] Kubernetes com RBAC + Network Policies? (casos 301-320)
- [ ] GitOps para deploy? (casos 901-950)
- [ ] Documentation atualizada?
- [ ] Runbooks para incidentes?
- [ ] Postmortem após incidentes?

---

**Versão:** 1.0.0
**Última atualização:** 2026-01-19
**Próxima revisão:** 2026-04-19 (trimestral)

---

**Feedback e contribuições:** Este documento é vivo e deve ser atualizado conforme novas tecnologias e práticas surgem. PRs são bem-vindos!
