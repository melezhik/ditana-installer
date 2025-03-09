#!raku

copy "examples/pacman1.conf", "/tmp/pacman.conf";

bash q:to /CODE/, %( :description<run ansible> );
  ansible-playbook -i localhost, \
  ../../airootfs//root/bind-mount/root/enable-arch-multilib-repo.yaml \
  -e "enable_multilib=y config_path=/tmp/pacman.conf"
CODE

task-run "tasks/enable-arch-multilib-repo-01", %(
  :path</tmp/pacman.conf>,
);
