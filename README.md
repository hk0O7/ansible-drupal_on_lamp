# ansible-drupal_on_lamp

Cross-platform Ansible project for installing the LAMP stack + Drupal and setting up a Drupal site.

Works on both Debian & RedHat Ansible OS families (tested on Ubuntu 22.04 LTS & Rocky Linux 8.8).


## Usage

1. Define (at least) your credentials for the new MySQL user as `drupal_mysql_user` and `drupal_mysql_pass` under `vars/mysql_user_creds.yml` as well as the ones for your Drupal admin user for the site as `drupal_user` and `drupal_pass` under `vars/drupal_admin_creds.yml`.
	
	Cypher them with `ansible-vault encrypt vars/{mysql_user,drupal_admin}_creds.yml`.

3. Run the main playbook with:
	```
	$ ansible-playbook -i /path/to/inventory --ask-vault-pass playbook.yml -l target_host_group
	```
