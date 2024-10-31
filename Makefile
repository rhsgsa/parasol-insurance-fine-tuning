MINIO_PROJ=ic-shared-minio
LLM_PROJ=ic-shared-llm

BASE:=$(shell dirname $(realpath $(lastword $(MAKEFILE_LIST))))

.PHONY: deploy
deploy: import-notebook-image upload-model deploy-model modify-showroom-git-repo deploy-workbench

.PHONY: import-notebook-image
import-notebook-image:
	oc apply -f $(BASE)/yaml/ilab-imagestream.yaml

.PHONY: upload-model
upload-model:
	@echo "removing any previous jobs..."
	-oc delete -n $(MINIO_PROJ) -f $(BASE)/yaml/upload-model.yaml 2>/dev/null || echo "nothing to delete"
	@/bin/echo -n "waiting for job to go away..."
	@while [ `oc get -n $(MINIO_PROJ) --no-headers job/upload-model 2>/dev/null | wc -l` -gt 0 ]; do \
	  /bin/echo -n "."; \
	done
	@echo "done"
	@echo "creating job to upload model to S3..."
	oc apply -n $(MINIO_PROJ) -f $(BASE)/yaml/upload-model.yaml
	@/bin/echo -n "waiting for pod to show up..."
	@while [ `oc get -n $(MINIO_PROJ) po -l job=upload-model --no-headers 2>/dev/null | wc -l` -lt 1 ]; do \
	  /bin/echo -n "."; \
	  sleep 5; \
	done
	@echo "done"
	@/bin/echo "waiting for pod to be ready..."
	oc wait -n $(MINIO_PROJ) `oc get -n $(MINIO_PROJ) po -o name -l job=upload-model` --for=condition=Ready --timeout=300s
	oc logs -n $(MINIO_PROJ) -f job/upload-model
	oc delete -n $(MINIO_PROJ) -f $(BASE)/yaml/upload-model.yaml


.PHONY: deploy-model
deploy-model:
	@echo "scale machineset"
	@scripts/scale-machineset

	@echo "deploying inference service..."
	oc apply -n $(LLM_PROJ) -f $(BASE)/yaml/finetuned.yaml
	oc rollout status deploy/finetuned -n ic-shared-llm --timeout=600s
	@scripts/check-http finetuned.ic-shared-llm.svc.cluster.local 8080

	oc apply -n $(LLM_PROJ) -f $(BASE)/yaml/unfinetuned.yaml
	oc rollout status deploy/unfinetuned -n ic-shared-llm --timeout=600s
	@scripts/check-http unfinetuned.ic-shared-llm.svc.cluster.local 8080

.PHONY: clean-model
clean-model:
	@echo "cleaning inference service..."
	oc delete -n $(LLM_PROJ) -f $(BASE)/yaml/finetuned.yaml


.PHONY: modify-showroom-git-repo
modify-showroom-git-repo:
	$(BASE)/scripts/modify-showroom-git-repo

.PHONY: deploy-workbench
deploy-workbench:
	$(BASE)/scripts/deploy-workbench