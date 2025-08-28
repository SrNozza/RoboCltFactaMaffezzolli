FROM ruby:3.0-alpine

# Instalar dependências do sistema
RUN apk add --no-cache build-base

# Criar diretório da aplicação
WORKDIR /app

# Copiar Gemfile primeiro para cache de dependências
COPY Gemfile* ./

# Instalar gems
RUN bundle install --without development test

# Copiar código da aplicação
COPY . .

# Criar diretório de logs
RUN mkdir -p logs

# Expor porta
EXPOSE 4570

# Configurar ambiente de produção
ENV RACK_ENV=production

# Comando para iniciar a aplicação
CMD ["ruby", "app.rb"]

