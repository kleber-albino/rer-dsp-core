# One solution, multiple instances

A new organization can adapt the platform to its own data without rewriting the application for each scenario.

## What you can configure

- Define the territorial structure of your instance.
- Configure the filters shown to users.
- Define KPIs, labels, and units of measurement.
- Organize geographic themes and sublayers.
- Publish your data through the configured infrastructure.

## Illustrative example

Run `./config.sh` to configure the instance through a guided wizard. The assistant generates `config/adopter/adopter-config.yaml` and the other instance files. The excerpt below shows how another instance can use **Country → Region → District** by changing only `installation.hierarchy`, without changing DSP code.

```yaml
# Illustrative excerpt from config/adopter/adopter-config.yaml

installation:
  hierarchy:
    level1:
      label: "State"
      placeholder: "Select a state"
    level2:
      label: "Municipality"
      placeholder: "Select a municipality"
    level3:
      label: "Area"
      placeholder: "Select an area"
  kpis:
    area_of_interest:
      label: "Registered properties"
      unit_of_measurement: "units"
      optional_label: "ha"
    theme_1:
      enabled: true
      label: "APP"
      unit_of_measurement: "ha"
    theme_2:
      enabled: true
      label: "Legal reserve"
      unit_of_measurement: "ha"
  screens:
    home_title: "Public geospatial data consultation"
    downloads_title: "Public data download"
    identifier:
      label: "CAR number"
      placeholder: "Enter the identifier"

map:
  group_names:
    territorial_division: "Territorial division"
    areas_of_interest: "Registration units"
  layers:
    level2:
      name: "Municipality"
      active_default: true
    area_of_interest:
      name: "Rural property"
      active_default: true

downloads:
  themes:
    - code: "CAR"
      label: "Rural Environmental Registry"
    - code: "APP_RL"
      label: "APP and legal reserve"
```

## How to instantiate the DSP?

1. **Get the code** — Access the [official repository](https://github.com/Rural-Environmental-Registry/dsp-core) and use the available DSP version as your starting point.
2. **Prepare the data** — Organize territorial data, registration units, attributes, and geographic themes for your instance.
3. **Configure the instance** — Run `./config.sh` and follow the guided wizard to define filters, territorial levels, KPIs, and layers. The script generates `config/adopter/adopter-config.yaml` and the instance JSON files.
4. **Publish and evolve** — Deploy your instance, connect the required services, and share improvements with the community.

## Frequently asked questions

### Is the DSP only for environmental data?

No. The DSP is the continuation of the [RER (Rural Environmental Registry)](https://www.digitalpublicgoods.net/r/rural-environmental-registry-registration-module) as a generic platform for geospatial data consultation and sharing. The [CAR Public Consultation](https://consulta.car.gov.br/) experience served as a reference, but the solution was designed to be reusable — each instance can define its own territorial structure, registration units, and geographic themes.

### Do I need to change the code to use a different territorial division?

No. Run `./config.sh` to define filters and territorial structure through the guided wizard; the assistant writes these options to `config/adopter/adopter-config.yaml`, allowing different hierarchies without values fixed in application logic.

### Can I define my own indicators?

Yes. Run `./config.sh` to configure KPIs through the guided wizard; calculated fields, labels, and units are saved in the instance configuration, with support for one to five indicators.

### How can I contribute?

Contributions are made through the [official GitHub repository](https://github.com/Rural-Environmental-Registry/dsp-core). Report issues, propose features, and submit improvements via pull request.
