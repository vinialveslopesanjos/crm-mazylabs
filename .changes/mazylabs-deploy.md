---
impacto: capacidade_nova
secao: adicionado
titulo: Fork MazyLabs recebe deploy automático após a validação da main
---

O fork MazyLabs valida a branch dev e publica imagens com o SHA completo do commit. Após integrar na main, o GitHub Actions atualiza somente o CRM quando os cinco checks obrigatórios passam. A VPS usa o Nginx existente, mantém as sessões do WhatsApp e faz backup antes de atualizar um ambiente já instalado. Uma falha ao iniciar os serviços tenta voltar às imagens anteriores; o banco não é restaurado automaticamente.
