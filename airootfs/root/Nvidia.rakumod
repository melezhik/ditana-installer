# Copyright (c) 2024, 2025 acrion innovations GmbH
# Authors: Stefan Zipproth, s.zipproth@acrion.ch
#
# This file is part of Ditana Installer, see
# https://github.com/acrion/ditana-installer and https://ditana.org/installer.
#
# Ditana Installer is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# Ditana Installer is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with Ditana Installer. If not, see <https://www.gnu.org/licenses/>.

use v6.d;
use Dialogs;
use Internet;
use Logging;
use NvidiaParser;
use PackageManagement;
use Settings;

sub get-nvidia-driver-version($pci-id) is export {
    CATCH {
        default {
            Logging.log("get-nvidia-driver-version: Unexpected error: $_");
            return Nil;
        }
    }
    
    show-dialog-raw('--infobox', "Checking the required driver version for your NVIDIA graphics card with PCI ID $pci-id...", 5, 52);
    
    my $nvidia_legacy_gpu_page = download-and-filter-nvidia-legacy-page();
    
    unless $nvidia_legacy_gpu_page {
        Logging.log("get-nvidia-driver-version: We fallback to a cached version of https://www.nvidia.com/en-us/drivers/unix/legacy-gpu to check if PCI ID $pci-id requires a legacy driver.");
        $nvidia_legacy_gpu_page='/root/cached_legacy_gpu_page.html'; # provided during ISO generation by build.sh
    }

    return parse-nvidia-page($nvidia_legacy_gpu_page, $pci-id);
}

sub check-nvidia($silent-exit-code, $reset-to-default) is export {
    return $silent-exit-code if $silent-exit-code != 0; # only do this if user navigated forward

    state $checked-nvidia is default(False);
    return $silent-exit-code if $checked-nvidia && !$reset-to-default;
    $checked-nvidia = True;

    my $s = Settings.instance;
    
    return $silent-exit-code unless $s.get('nvidia-pci-id');
    
    my $nvidia-driver-version = get-nvidia-driver-version($s.get('nvidia-pci-id'));
    
    my $url-nvidia-legacy='https://www.nvidia.com/en-us/drivers/unix/legacy-gpu/';
    my $instruction;
    
    if $nvidia-driver-version eq 'latest' {
        $s.modify-setting('install-nvidia-proprietary', 'arch-packages', ['nvidia-dkms']);
        $s.modify-setting('install-nvidia-proprietary', 'default-value', True);
        $s.modify-setting('install-nvidia-opensource',  'default-value', "`NOT install-nvidia-proprietary AND NOT install-nouveau`");
        $s.modify-setting('install-nouveau',            'default-value', "`NOT install-nvidia-opensource AND NOT install-nvidia-proprietary`");
        $s.set('install-nvidia-proprietary', True);

        $instruction = "Your graphics card with PCI ID {$s.get('nvidia-pci-id')} is not listed on $url-nvidia-legacy, indicating support for the latest proprietary NVIDIA driver version. You may want to switch to the open-source NVIDIA driver, please select «Help» for details.";
    } else {
        my $nvidia-proprietary-package = "nvidia-{$nvidia-driver-version}xx-dkms";
        $s.modify-setting('install-nvidia-proprietary', 'arch-packages', [$nvidia-proprietary-package]);
        
        show-dialog-raw('--infobox', "Checking available drivers for your NVIDIA graphics card with PCI ID {$s.get('nvidia-pci-id')}...", 14, 70);
        
        $instruction = "According to $url-nvidia-legacy, your graphics card with PCI ID {$s.get('nvidia-pci-id')} requires proprietary driver version $nvidia-driver-version. ";
        if $nvidia-driver-version.Numeric.defined && $nvidia-driver-version >= 470 {
            my $package-exists = run('pacman', '-Si', $nvidia-proprietary-package, :err(False), :out(False)).exitcode == 0;

            if $package-exists {
                $s.modify-setting('install-nvidia-proprietary', 'default-value', True);
                $s.modify-setting('install-nouveau',            'default-value', "`NOT install-nvidia-opensource AND NOT install-nvidia-proprietary`");
                $s.set('install-nvidia-proprietary', True);
            } else  {
                $s.modify-setting('install-nvidia-proprietary', 'available', "`False`");
                $s.modify-setting('install-nvidia-proprietary', 'default-value', False);
                $s.modify-setting('install-nouveau',           'default-value', True);
                $s.modify-setting('install-nvidia-opensource', 'default-value', "`NOT install-nouveau`");
                $s.set('install-nouveau', True);

                $instruction ~= "We recommend the Nouveau driver as there is no Arch package for this version. This is unexpected - please contact support@ditana.org to inform about this situation.";
            }
        } else {
            # We don’t even allow the old proprietary driver to be selected in this situation. To enable this, we first need to add this driver version to the Ditana repository.
            $s.modify-setting('install-nvidia-proprietary', 'available', "`False`");
            $s.modify-setting('install-nvidia-proprietary', 'default-value', False);

            $s.set('install-nouveau', True);
            $instruction ~= "For this version, it is recommended to install the open-source Nouveau driver instead. Please select «Help» for details.";
        }
        $s.modify-setting('install-nvidia-opensource', 'available', "`False`");
        $s.modify-setting('install-nvidia-opensource',  'default-value', False);
    }

    $s.modify-installation-step(('Configuration Categories', 'Expert Settings'), 'Hardware Support Options', 'instruction', $instruction);

    return $silent-exit-code
}
