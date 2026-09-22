# Che DevSpace

To configure this for use with Che DevSpaces (such as OpenShift DevSpaces), you can utilise the following:

```bash
kustomize build tmux-devspace/ | oc -n openshift-devspaces apply -f -
```

This should then create a ConfigMap, which gets picked up by the DevSpaces configuration, and allows for selection of this in the same way as any other DevSpace option.

## Using it from a project devfile

This editor supplies the terminal only — tmux and ttyd — never a text editor.
The editor you type into comes from the dev container image your own project
devfile declares. [`../nvim-udi`](../nvim-udi) is the image provided here for
that purpose, and [`../nvim-udi/devfile.yaml`](../nvim-udi/devfile.yaml) is a
complete project devfile you can copy.

Select it with the `che-editor` attribute, formed as
`<publisher>/<name>/<version>` from this definition's metadata:

```yaml
attributes:
  che-editor: kirikae/tmux-ttyd/latest
```

### merge-contribution

The `toolbox-runtime` component in `devfile.yaml` is not a container that gets
scheduled. It is a schema-only stand-in, marked
`controller.devfile.io/container-contribution: true`, whose `volumeMounts` and
ttyd `endpoint` are merged into the real dev container at start-up. That merge
is what lets this plugin attach a terminal to an image it knows nothing about.

The controller needs to know *which* container to merge into. Mark it
explicitly in your own devfile:

```yaml
components:
  - name: tools
    attributes:
      controller.devfile.io/merge-contribution: true
    container:
      image: ghcr.io/kirikae/terminal-devspaces/nvim-udi-ide:latest
```

Without that attribute the controller falls back to the first container with
`mountSources: true`. That is usually right for a single-container devfile and
usually wrong the moment you add a second one — a database or a sidecar can
end up hosting the terminal instead, which presents as a workspace that starts
cleanly but whose terminal has none of your tools in it.