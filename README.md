# 🦁 Robô Maffezzolli CLT Facta

Sistema de simulação de crédito consignado CLT integrado com API Facta.

## 🚀 Deploy Rápido no Railway

[![Deploy on Railway](https://railway.app/button.svg)](https://railway.app/template/new)

### Passos simples:
1. **Clique** no botão acima
2. **Configure** variáveis ambiente
3. **Deploy** automático
4. **Pronto!**

## ⚙️ Variáveis Ambiente

```
RACK_ENV=production
FACTA_LOGIN=96676
FACTA_PASSWORD=feaeqoxmbh3lzzpg3wpb
```

## 🔧 Funcionalidades

- ✅ **Processamento progressivo** (1 CPF por vez)
- ✅ **Persistência local** (não perde dados)
- ✅ **Pausar/Continuar** simulação
- ✅ **Exportação Excel** completa
- ✅ **API Facta integrada** (produção)
- ✅ **Interface responsiva**

## 📊 Endpoints API

- `GET /` - Interface principal
- `POST /api/simulate-single` - Processa 1 CPF
- `POST /api/simulate` - Processa lista
- `GET /api/export-excel` - Exporta Excel

## 🛠️ Desenvolvimento Local

```bash
# Instalar dependências
bundle install

# Executar aplicação
ruby app.rb

# Acessar
http://localhost:4570
```

## 📋 Estrutura

```
📁 robo-maffezzolli-facta/
├── 📄 app.rb                 ← Aplicação principal Ruby
├── 📁 views/
│   └── 📄 index.erb         ← Interface web
├── 📄 Gemfile               ← Dependências Ruby
├── 📄 railway.json          ← Configuração Railway
├── 📄 nixpacks.toml         ← Build configuration
└── 📄 README.md             ← Este arquivo
```

## 🌐 Demo

Teste o sistema funcionando: [URL será gerada após deploy]

## 📞 Suporte

Para dúvidas ou problemas, consulte a documentação ou abra uma issue.

---

🦁 **Made with Manus** | Robô Maffezzolli CLT Facta

