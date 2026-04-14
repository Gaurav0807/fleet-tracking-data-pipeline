FROM public.ecr.aws/lambda/python:3.10

# Install dbt-athena
RUN pip install --no-cache-dir dbt-athena-community

# Copy dbt project files
COPY dbt_project.yml profiles.yml packages.yml ${LAMBDA_TASK_ROOT}/
COPY models/ ${LAMBDA_TASK_ROOT}/models/
COPY macros/ ${LAMBDA_TASK_ROOT}/macros/

# Copy Lambda handler
COPY handler.py ${LAMBDA_TASK_ROOT}/

# Install dbt packages
RUN cd ${LAMBDA_TASK_ROOT} && dbt deps

CMD ["handler.lambda_handler"]
