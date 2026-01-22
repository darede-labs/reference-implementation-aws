################################################################################
# Simple S3 Bucket Test for Crossplane Validation
# Generated from template - DO NOT EDIT MANUALLY
################################################################################
apiVersion: s3.aws.upbound.io/v1beta2
kind: Bucket
metadata:
  name: {{ cluster_name }}-crossplane-test
  labels:
    testing: "true"
spec:
  forProvider:
    region: {{ region }}
    tags:
      Name: "{{ cluster_name }}-crossplane-test"
      ManagedBy: crossplane
      Environment: test
      {{ cloud_economics_tag_key }}: "{{ cloud_economics_tag_value }}"
  providerConfigRef:
    name: default
---
apiVersion: s3.aws.upbound.io/v1beta2
kind: BucketPublicAccessBlock
metadata:
  name: {{ cluster_name }}-crossplane-test-pab
spec:
  forProvider:
    bucketRef:
      name: {{ cluster_name }}-crossplane-test
    blockPublicAcls: true
    blockPublicPolicy: true
    ignorePublicAcls: true
    restrictPublicBuckets: true
  providerConfigRef:
    name: default
