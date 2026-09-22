# Che DevSpace

To configure this for use with Che DevSpaces (such as OpenShift DevSpaces), you can utilise the following:

```bash
kustomize build tmux-devspace/ | oc -n openshift-devspaces apply -f -
```

This should then create a ConfigMap, which gets picked up by the DevSpaces configuration, and allows for selection of this in the same way as any other DevSpace option.