################################################################################
# Example S3 Bucket via Crossplane
# Generated from template - DO NOT EDIT MANUALLY
# Source: platform/crossplane/examples/s3-bucket.yaml.tpl
################################################################################
apiVersion: s3.aws.upbound.io/v1beta1
kind: Bucket
metadata:
  name: {{ cluster_name }}-crossplane-test
  labels:
    testing.upbound.io/example-name: bucket
spec:
  forProvider:
    region: {{ region }}
    tags:
      Name: "{{ cluster_name }}-crossplane-test"
      ManagedBy: crossplane
      Environment: poc
      {{ cloud_economics_tag_key }}: "{{ cloud_economics_tag_value }}"
  providerConfigRef:
    name: default
---
apiVersion: s3.aws.upbound.io/v1beta1
kind: BucketPublicAccessBlock
metadata:
  name: {{ cluster_name }}-crossplane-test
spec:
  forProvider:
    bucket: {{ cluster_name }}-crossplane-test
    blockPublicAcls: true
    blockPublicPolicy: true
    ignorePublicAcls: true
    restrictPublicBuckets: true
    region: {{ region }}
  providerConfigRef:
    name: default
