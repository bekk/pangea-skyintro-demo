# pangea-skyintro-demo

Tilhørende kode for et foredrag under rekrutteringsarrangementet Pangea [https://oi.bekk.no](https://oi.bekk.no).

Demoen bruker en Azure Functions-app, samt Computer Vision og Speech fra Azure
Cognitive Services for å illustrere hvordan man kan en liten bilde-til-tekst-til-tale
applikasjon.

## Hvordan kjøre applikasjonen selv?

### Installasjon av nødvendige programmer

#### macOS

* [Installer brew](https://brew.sh).
* Installer Az CLI og Azure Functions Core Tools (v3)

  ```
  brew install azure-functions-core-tools@3 azure-cli
  ```

#### Ubuntu

* Az CLI:

  ```
  curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash
  ```

  * Eventuelt kan du følge manuelle steg [her](https://docs.microsoft.com/en-us/cli/azure/install-azure-cli-apt?view=azure-cli-latest).

* Azure Functions Core Tools (v3)
  * Følg instruksjonene [her](https://github.com/Azure/azure-functions-core-tools#linux).

#### Windows

`deploy.sh` er skrevet i Bash. En måte å kjøre dette skriptet fra Windows er å installere [WSL](https://docs.microsoft.com/en-us/windows/wsl/install-win10), og bruke WSL til å kjøre Ubuntu. Følg deretter installasjonsinstruksjonene for Ubuntu.

### Opprett en Azure-konto, og en subscription

* Gå til [https://azure.microsoft.com/](https://azure.microsoft.com/) og opprett en konto.
* Gå til [https://portal.azure.com/](https://portal.azure.com) og opprett en subscription.
  * Trykk på "Subscriptions"
  * Trykk på "Add"
  * Velg type. Her kan du f.eks. velge en som er rettet mot studenter og gir gratis forbruk opptil en viss sum.

### Kjør deploy-skriptet

* Klon dette repoet: `git clone https://github.com/bekk/pangea-skyintro-demo`.
* Naviger til repoet med kommando-linjen, og kjør `./deploy.sh`.
